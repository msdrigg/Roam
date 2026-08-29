#!/usr/bin/env python3
"""Tart VM orchestration for macOS screenshot capture.

Roam's macOS screenshot mode used to launch the real app on the host
with `-ScreenshotSavePath`, build a borderless 1440x900 NSWindow, and
snapshot its contentView. That fought for keyboard focus and stole the
host display during long capture matrices. This module moves the entire
capture into a Tart-managed macOS guest VM with a 2880x1800 display so
the host stays usable while screenshots run in the background.

External requirements (Homebrew):
    brew install cirruslabs/cli/tart
    brew install sshpass         # core tap works; hudochenkov/sshpass also fine

The orchestrator pulls the base image (default
`ghcr.io/cirruslabs/macos-tahoe-base:latest`, i.e. macOS 26) on first
run; subsequent runs reuse the long-lived `roam-screenshots` clone.
NOTE: the clone is pinned to whatever base it was first created from, so
after changing BASE_IMAGE_DEFAULT you MUST recreate it with:
`tart delete -f roam-screenshots`.

Typical usage:
    vm = TartVM(
        name="roam-screenshots",
        base_image="ghcr.io/cirruslabs/macos-tahoe-base:latest",
        display=(2880, 1800),
        host_app_dir=parent_of_built_roam_app,
        host_output_dir=writable_capture_dir,
    )
    vm.bring_up()
    vm.install_roam_app()
    vm.launch_roam(["-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting"])
    time.sleep(7)
    vm.screenshot_full_display("/tmp/state-1.png")
    vm.kill_roam()
    ...
    vm.stop()
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass, field


# Roam targets macOS 15.0+ (MACOSX_DEPLOYMENT_TARGET in the Xcode project),
# so the guest must be Sequoia or newer. We ship App Store screenshots that
# reflect the current OS look, so the default is macOS 26 (Tahoe). To avoid
# the screen-recording "private window picker bypass" TCC dialog over our
# captures (introduced in Sequoia, still present in Tahoe), we route
# `screencapture` through `sudo launchctl asuser <uid>` (see
# TartVM.screencapture_*) so it runs in the GUI user's launchd session
# rather than SSH's sandboxed context.
BASE_IMAGE_DEFAULT = "ghcr.io/cirruslabs/macos-tahoe-base:latest"
VM_NAME_DEFAULT = "roam-screenshots"
DISPLAY_DEFAULT = (2880, 1800)
SSH_USER = "admin"
SSH_PASSWORD = "admin"
ROAM_BUNDLE_ID = "com.msdrigg.roam"

# Tart mounts shared directories under this path inside the guest.
GUEST_SHARED_ROOT = "/Volumes/My Shared Files"
SHARE_APP = "roam-app"
SHARE_OUT = "roam-out"
GUEST_APP_INSTALL_PATH = "/Users/admin/RoamScreenshotApp/Roam.app"
# Name of the zipped app placed (by build_roam_app) in the host app dir,
# which the guest sees via the read-only roam-app share.
GUEST_APP_ZIP_NAME = "Roam-screenshots.zip"

# Static desktop wallpaper shown behind the captured windows (the
# "Greenland Evening" aerial still). A static image is used rather than
# the live aerial because aerials/video wallpapers don't reliably render
# under the headless `--no-graphics` capture. Set on every bring_up.
WALLPAPER_HOST_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "screenshots", "mac-desktop-background.png",
)
WALLPAPER_GUEST_PATH = "/Users/admin/Pictures/roam-screenshot-wallpaper.png"
WALLPAPER_SHARE_NAME = "roam-wallpaper.png"

SSH_OPTIONS = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "PasswordAuthentication=yes",
    "-o", "PubkeyAuthentication=no",
    "-o", "PreferredAuthentications=password",
    "-o", "LogLevel=ERROR",
    "-o", "ConnectTimeout=10",
    # ControlMaster multiplexes SSH calls over a single TCP/auth session
    # so we don't trip sshd's MaxAuthTries / per-source rate-limiting
    # when running many small commands in quick succession.
    "-o", "ControlMaster=auto",
    "-o", "ControlPath=/tmp/roam-tart-ssh-%C",
    "-o", "ControlPersist=300",
]


def ensure_dependencies() -> None:
    """Raise with install instructions if tart/sshpass are missing."""
    missing = []
    if shutil.which("tart") is None:
        missing.append("`brew install cirruslabs/cli/tart`")
    if shutil.which("sshpass") is None:
        missing.append("`brew install sshpass`")
    if missing:
        raise RuntimeError(
            "Missing required tools for macOS screenshot capture. Install:\n  "
            + "\n  ".join(missing)
        )


@dataclass
class TartVM:
    name: str
    base_image: str
    display: tuple[int, int]
    host_app_dir: str
    host_output_dir: str

    _ip: str | None = field(default=None, init=False, repr=False)
    _run_proc: subprocess.Popen | None = field(default=None, init=False, repr=False)
    _run_log_fh: object | None = field(default=None, init=False, repr=False)
    _app_installed: bool = field(default=False, init=False, repr=False)
    _admin_uid: int | None = field(default=None, init=False, repr=False)

    # ---------- tart wrappers ----------

    def _list_entries(self) -> list[dict]:
        proc = subprocess.run(
            ["tart", "list", "--format", "json"],
            capture_output=True, text=True, check=False,
        )
        if proc.returncode != 0:
            return []
        try:
            return json.loads(proc.stdout)
        except (json.JSONDecodeError, ValueError):
            return []

    def _entry(self, name: str, source: str | None = None) -> dict | None:
        for entry in self._list_entries():
            if entry.get("Name") != name:
                continue
            if source is not None and entry.get("Source") != source:
                continue
            return entry
        return None

    def exists_local(self) -> bool:
        return self._entry(self.name, source="local") is not None

    def is_running(self) -> bool:
        entry = self._entry(self.name)
        if not entry:
            return False
        return (entry.get("State") or "").lower() == "running"

    # ---------- lifecycle ----------

    def bring_up(self, *, headless: bool = True) -> None:
        """Create + configure (idempotent) and start the VM, then wait for SSH.

        Always takes ownership of the running instance. A leftover
        `tart run` orphaned by an aborted earlier run (atexit teardown
        skipped on SIGKILL / double Ctrl-C) keeps the VM alive with the
        *previous* run's `--dir=roam-out:<old tmp>` mount. Reusing it
        would send every capture into a now-deleted host dir - the guest
        writes `/Volumes/My Shared Files/roam-out/capture-*.png` fine, but
        the host polls *this* run's tmp dir and never sees it
        ("screencapture wrote ... but host never saw ..."). So if the VM
        is already running we stop it and start our own with the correct
        mounts, then verify the share actually round-trips before any
        capture relies on it.
        """
        if not self.exists_local():
            # `tart clone` of a remote OCI URL auto-pulls if the image
            # isn't in `~/.tart/cache/OCIs/...`, and uses the cache
            # otherwise - no separate `tart pull` step needed. Going
            # through pull explicitly re-validates layers against the
            # registry, which is what triggered the "network connection
            # was lost" retry storm we saw on transient connectivity.
            print(
                f"[tart] cloning {self.base_image} -> {self.name} "
                f"(first run pulls ~20GB; subsequent runs use the local cache)"
            )
            subprocess.run(
                ["tart", "clone", self.base_image, self.name], check=True
            )

        self._configure()

        if self.is_running():
            # We didn't start this instance, so we can't trust (or retag)
            # its shared-dir mounts. Stop it and boot our own.
            print(
                f"[tart] {self.name} already running (orphaned from an earlier "
                f"run?); stopping it so this run owns the shared-dir mounts"
            )
            self.stop()
            self._wait_until_stopped()

        self._start_background(headless=headless)
        self.wait_for_ip()
        self.wait_for_ssh()
        # Ensure the guest boots at the target resolution (one-time
        # permanent set + reboot; persists on disk thereafter). Done in
        # headless mode only - the interactive setup flow drives this
        # itself so the user can watch.
        if headless:
            self.ensure_guest_display()

        # The whole capture pipeline depends on the writable roam-out
        # share mapping guest -> this run's host_output_dir. Verify it
        # round-trips now, with a clear error, rather than letting every
        # capture fail later with the opaque "host never saw" message.
        if not self._verify_output_share():
            raise RuntimeError(
                f"[tart] the roam-out share is not reaching the host: the "
                f"guest wrote a probe file under "
                f"{GUEST_SHARED_ROOT}/{SHARE_OUT} but it never appeared at "
                f"{self.host_output_dir}. This is a virtio-fs sharing "
                f"problem, not a capture problem."
            )

        # Match the host look: Dark appearance + the chosen wallpaper behind
        # the captured windows.
        self.set_dark_mode()
        self.set_wallpaper()

    def set_dark_mode(self) -> None:
        """Switch the guest to Dark appearance. The app forces a dark color
        scheme for its own views, but the system appearance still drives the
        menu bar, window-backdrop materials, and overall tint, so the guest
        must be in Dark mode for captures to match the host. Best-effort."""
        uid = self._detect_admin_uid()
        applescript = (
            'tell application "System Events" to tell appearance '
            'preferences to set dark mode to true'
        )
        proc = self.ssh(
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl asuser {uid} "
            f"osascript -e {shlex.quote(applescript)}",
            check=False, timeout=40,
        )
        if proc.returncode != 0:
            print(
                f"  Warning: set dark mode failed "
                f"(stdout={proc.stdout!r} stderr={proc.stderr!r})"
            )
        else:
            print("[tart] set guest appearance to Dark")

    def set_wallpaper(self) -> None:
        """Set the guest desktop to the static screenshot wallpaper.

        Copies the repo image into the guest (via the writable share, to a
        persistent path since the share unmounts on stop) and points every
        desktop at it with System Events. A static image set this way
        renders under the headless capture; live aerials/video wallpapers
        do not. Best-effort - logs a warning rather than aborting the run."""
        if not os.path.isfile(WALLPAPER_HOST_PATH):
            print(
                f"  Warning: wallpaper {WALLPAPER_HOST_PATH} missing; "
                f"keeping the guest's current desktop"
            )
            return
        staged = os.path.join(self.host_output_dir, WALLPAPER_SHARE_NAME)
        try:
            shutil.copy(WALLPAPER_HOST_PATH, staged)
        except OSError as e:
            print(f"  Warning: staging wallpaper failed: {e}")
            return
        share_src = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}/{WALLPAPER_SHARE_NAME}"
        uid = self._detect_admin_uid()
        applescript = (
            f'tell application "System Events" to set picture of every '
            f'desktop to "{WALLPAPER_GUEST_PATH}"'
        )
        cmd = (
            f"mkdir -p {shlex.quote(os.path.dirname(WALLPAPER_GUEST_PATH))} && "
            f"cp {shlex.quote(share_src)} {shlex.quote(WALLPAPER_GUEST_PATH)} && "
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl asuser {uid} "
            f"osascript -e {shlex.quote(applescript)}"
        )
        proc = self.ssh(cmd, check=False, timeout=60)
        try:
            os.remove(staged)
        except OSError:
            pass
        if proc.returncode != 0:
            print(
                f"  Warning: set wallpaper failed "
                f"(stdout={proc.stdout!r} stderr={proc.stderr!r})"
            )
        else:
            print("[tart] set desktop wallpaper (Greenland Evening still)")

    def _wait_until_stopped(self, timeout: float = 60.0) -> None:
        """Block until `tart` reports the VM is no longer running, so a
        fresh `tart run` won't collide with a still-shutting-down instance
        ('VM is already running')."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if not self.is_running():
                return
            time.sleep(0.5)
        print(
            f"  Warning: {self.name} still reports running after {timeout}s; "
            f"attempting to start anyway"
        )

    def _verify_output_share(self) -> bool:
        """Round-trip a marker file from the guest's roam-out share to the
        host dir this run polls. Returns False if the marker never lands
        host-side (the share maps elsewhere, or virtio-fs isn't syncing)."""
        guest_share = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}"
        name = f"share-probe-{int(time.time() * 1000)}.txt"
        guest_path = f"{guest_share}/{name}"
        self.ssh(
            f"echo ok > {shlex.quote(guest_path)} && sync",
            check=False, timeout=30,
        )
        host_path = os.path.join(self.host_output_dir, name)
        ok = False
        for _ in range(40):
            if os.path.isfile(host_path):
                ok = True
                break
            time.sleep(0.25)
        if ok:
            try:
                os.remove(host_path)
            except OSError:
                pass
        else:
            self.ssh(
                f"rm -f {shlex.quote(guest_path)}", check=False, timeout=20
            )
        return ok

    def _configure(self) -> None:
        os.makedirs(self.host_output_dir, exist_ok=True)
        w, h = self.display
        # `tart set --display` configures the virtual display device, but
        # the cirruslabs base image's WindowServer still boots at its
        # own saved resolution - the actual mode is forced post-boot in
        # ensure_guest_display(). We still set the device size here so the
        # device is at least capable of the target mode.
        display_arg = f"--display={w}x{h}"
        print(f"[tart] configuring {self.name}: display device {w}x{h}")
        subprocess.run(
            ["tart", "set", self.name, display_arg],
            check=True,
        )

    def _start_background(self, headless: bool = True) -> None:
        log_path = os.path.join(tempfile.gettempdir(), f"tart-{self.name}.log")
        dir_args = [
            f"--dir={SHARE_APP}:{self.host_app_dir}:ro",
            f"--dir={SHARE_OUT}:{self.host_output_dir}",
        ]
        mode_args = ["--no-graphics"] if headless else []
        mode_label = "headlessly" if headless else "with host window"
        print(
            f"[tart] starting {self.name} {mode_label} "
            f"(app(ro)={self.host_app_dir}, "
            f"out(rw)={self.host_output_dir}, logs: {log_path})"
        )
        self._run_log_fh = open(log_path, "w")
        # --no-graphics: virt framework still attaches a virtual display
        # device, so WindowServer + screencapture work; just no host window
        # opens, so it can't interrupt your host work. Without that flag,
        # tart opens a host-side window mirroring the guest display - used
        # for the one-time TCC-grant interactive setup flow.
        self._run_proc = subprocess.Popen(
            ["tart", "run", *mode_args, *dir_args, self.name],
            stdout=self._run_log_fh,
            stderr=subprocess.STDOUT,
        )

    def wait_for_ip(self, timeout: float = 240.0) -> str:
        deadline = time.time() + timeout
        last_err: str = ""
        while time.time() < deadline:
            proc = subprocess.run(
                ["tart", "ip", "--wait", "5", self.name],
                capture_output=True, text=True, check=False, timeout=15,
            )
            ip = (proc.stdout or "").strip()
            if proc.returncode == 0 and ip:
                self._ip = ip
                print(f"[tart] {self.name} ip={ip}")
                return ip
            last_err = (proc.stderr or "").strip() or "no ip yet"
            time.sleep(2.0)
        raise RuntimeError(
            f"[tart] timed out waiting for {self.name} IP after {timeout}s "
            f"(last: {last_err!r})"
        )

    def wait_for_ssh(self, timeout: float = 240.0) -> None:
        deadline = time.time() + timeout
        last_msg: str = ""
        while time.time() < deadline:
            try:
                proc = self._ssh_raw("echo ok", check=False, timeout=15)
            except subprocess.TimeoutExpired:
                # A cold-booting guest can accept the TCP connection but
                # stall before the SSH banner/auth completes, so a single
                # attempt hits the 15s subprocess timeout. That's expected
                # mid-boot - keep polling until the overall deadline rather
                # than aborting the whole wait.
                last_msg = "ssh attempt timed out (guest still booting)"
                time.sleep(3.0)
                continue
            if proc.returncode == 0 and "ok" in (proc.stdout or ""):
                print(f"[tart] {self.name} SSH ready")
                return
            last_msg = (proc.stderr or proc.stdout or "").strip().splitlines()[-1:]
            last_msg = last_msg[0] if last_msg else ""
            time.sleep(3.0)
        raise RuntimeError(
            f"[tart] timed out waiting for SSH on {self.name} (last: {last_msg!r})"
        )

    def stop(self, timeout: float = 30.0) -> None:
        if not self.is_running():
            return
        print(f"[tart] stopping {self.name}")
        subprocess.run(
            ["tart", "stop", "--timeout", str(int(timeout)), self.name],
            check=False, capture_output=True,
        )
        if self._run_proc is not None:
            try:
                self._run_proc.wait(timeout=timeout + 10)
            except subprocess.TimeoutExpired:
                self._run_proc.kill()
        if self._run_log_fh is not None:
            try:
                self._run_log_fh.close()
            except OSError:
                pass

    # ---------- ssh ----------

    def _ssh_raw(
        self, command: str, *, check: bool, timeout: float | None,
    ) -> subprocess.CompletedProcess:
        target = f"{SSH_USER}@{self._ip or '0.0.0.0'}"
        argv = [
            "sshpass", "-p", SSH_PASSWORD,
            "ssh", *SSH_OPTIONS, target, command,
        ]
        return subprocess.run(
            argv, capture_output=True, text=True,
            check=check, timeout=timeout,
        )

    # Network-level transients we should retry through. "No route to host"
    # showed up mid-run; "connection refused" / "timed out" are similar.
    _SSH_RETRY_PATTERNS = (
        "no route to host",
        "connection refused",
        "connection timed out",
        "operation timed out",
        "connection reset by peer",
    )

    def ssh(
        self, command: str, *, check: bool = True, timeout: float | None = 120,
        retries: int = 3,
    ) -> subprocess.CompletedProcess:
        if self._ip is None:
            self.wait_for_ip()
        last: subprocess.CompletedProcess | None = None
        for attempt in range(retries):
            try:
                proc = self._ssh_raw(command, check=False, timeout=timeout)
            except subprocess.TimeoutExpired as e:
                if attempt >= retries - 1:
                    raise
                print(
                    f"  [tart] ssh timed out (attempt {attempt + 1}/{retries}); "
                    f"refreshing IP and retrying"
                )
                self._refresh_ip_after_transient()
                continue
            last = proc
            if proc.returncode == 0:
                return proc
            blob = ((proc.stderr or "") + (proc.stdout or "")).lower()
            transient = any(p in blob for p in self._SSH_RETRY_PATTERNS)
            if not transient or attempt >= retries - 1:
                if check and proc.returncode != 0:
                    raise subprocess.CalledProcessError(
                        proc.returncode, proc.args, proc.stdout, proc.stderr
                    )
                return proc
            print(
                f"  [tart] ssh transient ({proc.returncode}): "
                f"{(proc.stderr or '').strip().splitlines()[-1] if proc.stderr else ''} - "
                f"retry {attempt + 1}/{retries}"
            )
            self._refresh_ip_after_transient()
        # Unreachable in practice; appease type-checkers.
        assert last is not None
        return last

    def _refresh_ip_after_transient(self) -> None:
        """Re-resolve the VM IP - guest DHCP can rotate addresses between
        captures and the cached IP goes stale."""
        time.sleep(2.0)
        proc = subprocess.run(
            ["tart", "ip", "--wait", "5", self.name],
            capture_output=True, text=True, check=False, timeout=15,
        )
        ip = (proc.stdout or "").strip()
        if proc.returncode == 0 and ip and ip != self._ip:
            print(f"  [tart] IP changed {self._ip} -> {ip}")
            self._ip = ip

    # ---------- guest provisioning ----------

    def install_roam_app(self) -> None:
        """Extract the host-built Roam.app zip into the guest, re-sign it
        ad-hoc, clear quarantine, disable Gatekeeper, and pre-grant the
        TCC entries the capture path needs.

        Why a zip, not a directory copy? Copying the bundle through the
        virtio-fs directory share rewrites per-file metadata, which
        invalidates `_CodeSignature/CodeResources` ("invalid resource
        directory"). build_roam_app zips the bundle (preserving its
        contents byte-for-byte); extracting that single file in the guest
        reproduces an intact bundle.

        Why re-sign after extracting a validly-signed bundle? The host
        build signs with hardened-runtime / library-validation flags that
        the guest's AMFI rejects (`launchd` spawn fails, POSIX 162
        EBADEXEC) even though the signature itself is valid. Re-signing
        ad-hoc (`--sign -`) in the guest drops those flags. The Debug
        build must also be produced with ENABLE_DEBUG_DYLIB=NO (see
        build_roam_app) so there's no split debug dylib to fail
        `--deep` strict validation.

        Why touch TCC.db directly? The ScreenCaptureKit screen-recording
        dialog (Sequoia and later, incl. Tahoe / macOS 26) and the
        Accessibility prompt are pre-authorized there (see _grant_tcc);
        the cirruslabs base image ships with SIP disabled so the writes
        are allowed."""
        if self._app_installed:
            return
        guest_zip = f"{GUEST_SHARED_ROOT}/{SHARE_APP}/{GUEST_APP_ZIP_NAME}"
        install_dir = os.path.dirname(GUEST_APP_INSTALL_PATH)
        bootstrap = (
            f"set -e; "
            f"rm -rf {shlex.quote(install_dir)}; "
            f"mkdir -p {shlex.quote(install_dir)}; "
            # Extract the bundle from the byte-for-byte zip; the embedded
            # resource signature stays intact (unlike a directory copy).
            f"ditto -x -k {shlex.quote(guest_zip)} {shlex.quote(install_dir)}/; "
            f"xattr -dr com.apple.quarantine {shlex.quote(GUEST_APP_INSTALL_PATH)} || true; "
            # Re-sign ad-hoc to drop the host's hardened-runtime flags.
            f"codesign --force --deep --sign - {shlex.quote(GUEST_APP_INSTALL_PATH)}; "
            f"codesign -dvvv {shlex.quote(GUEST_APP_INSTALL_PATH)} 2>&1 | head -6; "
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S spctl --master-disable || true; "
        )
        print(f"[tart] installing Roam.app -> {GUEST_APP_INSTALL_PATH}")
        proc = self.ssh(bootstrap, check=False, timeout=300)
        if proc.returncode != 0:
            raise RuntimeError(
                f"[tart] installing Roam.app failed: "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
            )
        for line in (proc.stdout or "").splitlines():
            print(f"  [guest codesign] {line}")
        # Pre-grant TCC (Screen Recording + Accessibility) so captures and
        # the AX window resize run without prompts, then clear/disable
        # notification banners. The display is set up once in bring_up().
        self._grant_tcc()
        self._clear_notifications()
        self._app_installed = True

    def ensure_guest_display(self) -> None:
        """Make the guest boot at `self.display`.

        Runtime display-mode switching (CGConfigure...`.forSession`)
        breaks WindowServer compositing in the VM - app windows register
        but never reach the framebuffer, so captures show only the
        wallpaper. Switching `.permanently` writes the windowserver
        displays prefs to the VM disk; after a reboot macOS initializes
        WindowServer cleanly at the target mode and compositing works.

        Because the pref persists on disk, this is a one-time cost per
        VM: we read the current resolution first and only set+reboot
        when it doesn't already match. Subsequent runs (and even
        `tart stop`/`start` cycles) boot straight into the target mode."""
        w, h = self.display
        cur = self._read_guest_resolution()
        if cur == (w, h):
            print(f"[tart] guest display already {w}x{h}")
            return
        print(
            f"[tart] guest display is {cur}; setting {w}x{h} permanently "
            f"and rebooting (one-time)"
        )
        uid = self._detect_admin_uid()
        swift_src = f'''import Foundation
import CoreGraphics
let display = CGMainDisplayID()
let modes = CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode] ?? []
guard let target = modes.first(where: {{ $0.width == {w} && $0.height == {h} }}) else {{
    FileHandle.standardError.write("no {w}x{h} mode available\\n".data(using: .utf8)!)
    exit(1)
}}
var config: CGDisplayConfigRef?
CGBeginDisplayConfiguration(&config)
CGConfigureDisplayWithDisplayMode(config!, display, target, nil)
let rc = CGCompleteDisplayConfiguration(config!, .permanently)
print("complete rc=\\(rc.rawValue)")
'''
        script_path = "/tmp/roam-set-display.swift"
        stage = f"cat > {script_path} <<'__SWIFT_EOF__'\n{swift_src}__SWIFT_EOF__"
        proc = self.ssh(stage, check=False, timeout=20)
        if proc.returncode != 0:
            print(f"  Warning: staging set-display swift failed: {proc.stderr!r}")
            return
        proc = self.ssh(
            f"echo {shlex.quote(SSH_PASSWORD)} | "
            f"sudo -S launchctl asuser {uid} swift {script_path}",
            check=False, timeout=30,
        )
        for line in (proc.stdout or "").splitlines():
            if line.strip():
                print(f"  [guest display] {line}")
        # Reboot and wait for the VM to come back at the new mode.
        self.ssh(
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S shutdown -r now",
            check=False, timeout=15,
        )
        print("[tart] rebooting guest to apply display mode ...")
        time.sleep(8.0)  # let it actually go down before we poll
        self._ip = None
        self.wait_for_ip()
        self.wait_for_ssh()
        after = self._read_guest_resolution()
        if after == (w, h):
            print(f"[tart] guest display now {w}x{h}")
        else:
            print(
                f"  Warning: guest display is {after} after reboot, "
                f"expected {w}x{h}; captures may be the wrong size"
            )

    def _read_guest_resolution(self) -> tuple[int, int] | None:
        uid = self._detect_admin_uid()
        proc = self.ssh(
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl asuser {uid} "
            f"swift -e 'import AppKit; let f = NSScreen.main!.frame; "
            f"print(Int(f.width), Int(f.height))'",
            check=False, timeout=30,
        )
        if proc.returncode != 0:
            return None
        parts = (proc.stdout or "").strip().split()
        if len(parts) == 2 and parts[0].isdigit() and parts[1].isdigit():
            return (int(parts[0]), int(parts[1]))
        return None

    def resize_roam_window(self, x: int, y: int, width: int, height: int) -> None:
        """Position + size Roam's main window via the Accessibility API.

        SwiftUI brings the window up at a restored/ideal size that often
        doesn't fill the 2880x1800 screen nicely; an AX resize gives a
        deterministic frame. Requires the Accessibility TCC grant (added
        in _grant_tcc). Best-effort - logs a warning on failure."""
        uid = self._detect_admin_uid()
        swift_src = f'''import AppKit
import ApplicationServices
guard let app = NSRunningApplication.runningApplications(
    withBundleIdentifier: "{ROAM_BUNDLE_ID}").first else {{ exit(1) }}
let ax = AXUIElementCreateApplication(app.processIdentifier)
var wRef: CFTypeRef?
AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wRef)
guard let ws = wRef as? [AXUIElement], let win = ws.first else {{ exit(1) }}
var pos = CGPoint(x: {x}, y: {y})
var size = CGSize(width: {width}, height: {height})
AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pos)!)
AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
print("resized")
'''
        script_path = "/tmp/roam-resize.swift"
        stage = f"cat > {script_path} <<'__SWIFT_EOF__'\n{swift_src}__SWIFT_EOF__"
        if self.ssh(stage, check=False, timeout=20).returncode != 0:
            print("  Warning: staging resize swift failed")
            return
        proc = self.ssh(
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl asuser {uid} "
            f"swift {script_path}",
            check=False, timeout=30,
        )
        if proc.returncode != 0 or "resized" not in (proc.stdout or ""):
            print(
                f"  Warning: AX resize of Roam window failed "
                f"(stdout={proc.stdout!r} stderr={proc.stderr!r})"
            )

    def _clear_notifications(self) -> None:
        """Clear notification banners and stop new ones from accumulating.

        Two distinct nuisances land in our captures:
          - "Background Items Added" alerts (top-right), posted by the BTM
            notification agent whenever a login item / agent / extension
            is registered (Roam's widget extension triggers this on first
            launch). These persist in the usernoted database until
            dismissed, so killing the daemon alone doesn't clear them -
            we delete the db file and restart the daemons.
          - The macOS "screen recording" reminder dialog (center),
            owned by UserNotificationCenter - handled per-capture in
            screencapture().

        We also disable the BTM notification agent so no new
        "Background Items Added" banners post during the run."""
        db = "/Users/admin/Library/Group Containers/group.com.apple.usernoted/db2"
        uid = self._detect_admin_uid()
        cmd = (
            # Stop new BTM "Background Items Added" banners from posting.
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl "
            f"  disable gui/{uid}/com.apple.btmnotificationagent 2>/dev/null || true; "
            # Wipe the persisted notification store and restart the daemons
            # so any already-queued banners are gone.
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S rm -f "
            f"  {shlex.quote(db + '/db')} {shlex.quote(db + '/db-shm')} "
            f"  {shlex.quote(db + '/db-wal')} 2>/dev/null || true; "
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S killall "
            f"  usernoted NotificationCenter UserNotificationCenter 2>/dev/null || true"
        )
        print("[tart] clearing notification banners")
        self.ssh(cmd, check=False, timeout=30)

    def _grant_tcc(self) -> None:
        """Insert TCC grants so neither the screen-recording bypass
        dialog (Sequoia and later, incl. Tahoe) nor an Accessibility
        prompt ever fires.

        The cirruslabs base image runs with SIP disabled, so a direct
        sqlite3 write to `/Library/Application Support/com.apple.TCC/TCC.db`
        is allowed. After writing, `killall tccd` forces the daemon to
        re-read the grants for the in-flight session.

        Grants two services to every identity in the SSH→launchctl→swift/
        screencapture chain:
          - kTCCServiceScreenCapture - for the actual captures
          - kTCCServiceAccessibility - for the AX window resize
        """
        # (client, client_type): 0 = bundle id, 1 = binary path.
        clients: list[tuple[str, int]] = [
            ("com.apple.sshd-session", 0),
            ("/usr/sbin/screencapture", 1),
            ("/usr/libexec/sshd-session", 1),
            ("/usr/sbin/sshd", 1),
            ("/bin/launchctl", 1),
            ("/usr/bin/swift", 1),
            ("/bin/sh", 1),
        ]
        services = ["kTCCServiceScreenCapture", "kTCCServiceAccessibility"]
        rows = ", ".join(
            f"('{svc}', '{client}', {client_type}, 2, 4, 1, 0, 'UNUSED', 0)"
            for svc in services
            for client, client_type in clients
        )
        sql = (
            "INSERT OR REPLACE INTO access ("
            "service, client, client_type, auth_value, auth_reason, "
            "auth_version, indirect_object_identifier_type, "
            "indirect_object_identifier, flags) VALUES "
            f"{rows};"
        )
        cmd = (
            f"echo {shlex.quote(SSH_PASSWORD)} | "
            f"sudo -S sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' "
            f"{shlex.quote(sql)} && "
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S killall tccd 2>/dev/null; "
            f"true"
        )
        print("[tart] granting Screen Recording + Accessibility TCC entries")
        proc = self.ssh(cmd, check=False, timeout=30)
        if proc.returncode != 0:
            print(
                f"  Warning: TCC grant write failed (stderr={proc.stderr!r}). "
                f"Captures may show the macOS screen-recording dialog."
            )

    # ---------- driving the Roam app ----------

    @staticmethod
    def _format_args(args: list[str]) -> str:
        return " ".join(shlex.quote(a) for a in args)

    def launch_roam(
        self,
        launch_args: list[str],
        *,
        locale: str | None = None,
        env: dict[str, str] | None = None,
    ) -> None:
        """Kill any running Roam, then launch a fresh instance with the
        given launch args. Uses `open -n` so each call gets a fresh
        process and the launch args take effect on the new instance.

        `locale` (BCP-47 like `fr-FR`) becomes `-AppleLanguages (fr-FR)
        -AppleLocale fr_FR`."""
        self.install_roam_app()
        self.kill_roam()

        full_args = list(launch_args)
        if locale:
            full_args = [
                "-AppleLanguages", f"({locale})",
                "-AppleLocale", locale.replace("-", "_"),
                *full_args,
            ]

        env_prefix = ""
        if env:
            env_prefix = " ".join(
                f"{k}={shlex.quote(v)}" for k, v in env.items()
            ) + " "

        cmd = (
            f"{env_prefix}open -n {shlex.quote(GUEST_APP_INSTALL_PATH)} "
            f"--args {self._format_args(full_args)}"
        )
        proc = self.ssh(cmd, check=False, timeout=60)
        if proc.returncode != 0:
            raise RuntimeError(
                f"[tart] launch_roam failed: stderr={proc.stderr!r}"
            )

    def kill_roam(self) -> None:
        # `pkill -9 -x Roam` only matches the exact process name. Use -f
        # against the install path to catch helper processes too.
        self.ssh(
            f"pkill -9 -f {shlex.quote(GUEST_APP_INSTALL_PATH)} || true",
            check=False, timeout=30,
        )

    # ---------- capture ----------

    def _detect_admin_uid(self) -> int:
        if self._admin_uid is not None:
            return self._admin_uid
        proc = self.ssh(f"id -u {SSH_USER}", check=False, timeout=20)
        uid: int | None = None
        if proc.returncode == 0:
            try:
                uid = int((proc.stdout or "").strip())
            except ValueError:
                pass
        # Cirrus base images use 501 for the first admin user.
        self._admin_uid = uid if uid is not None else 501
        return self._admin_uid

    def screencapture(self, args: list[str]) -> subprocess.CompletedProcess:
        """Run `screencapture` in the GUI user's launchd session.

        With the Screen Recording TCC grant in place (see _grant_tcc),
        `launchctl asuser <uid> screencapture` captures real app content.
        macOS still posts an asynchronous "screen recording" reminder
        dialog (owned by UserNotificationCenter) shortly after a capture;
        we `killall UserNotificationCenter` immediately before each
        capture so any dialog left over from the previous capture is gone
        before we grab the framebuffer. screencapture itself is
        synchronous and grabs instantly, so the just-spawned dialog never
        makes it into the frame."""
        uid = self._detect_admin_uid()
        quoted = " ".join(shlex.quote(a) for a in args)
        cmd = (
            # Dismiss any lingering screen-recording reminder dialog.
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S killall "
            f"  UserNotificationCenter 2>/dev/null; "
            f"echo {shlex.quote(SSH_PASSWORD)} | sudo -S launchctl asuser {uid} "
            f"  /usr/sbin/screencapture {quoted}"
        )
        return self.ssh(cmd, check=False, timeout=60)

    def screenshot_full_display(self, dest_png: str) -> None:
        """Capture the guest's main display and copy the PNG back to the
        host through the writable shared folder."""
        guest_share_dir = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}"
        guest_filename = f"capture-{int(time.time() * 1000)}.png"
        guest_path = f"{guest_share_dir}/{guest_filename}"
        proc = self.screencapture(["-x", "-t", "png", guest_path])
        if proc.returncode != 0:
            raise RuntimeError(
                f"[tart] screencapture failed: stdout={proc.stdout!r} "
                f"stderr={proc.stderr!r}"
            )
        # Sync to force the virtiofs write through. A separate ssh keeps
        # the screencapture command surface minimal.
        self.ssh("sync", check=False, timeout=20)
        host_path = os.path.join(self.host_output_dir, guest_filename)
        for _ in range(40):
            if os.path.isfile(host_path) and os.path.getsize(host_path) > 0:
                break
            time.sleep(0.25)
        if not os.path.isfile(host_path):
            raise RuntimeError(
                f"[tart] screencapture wrote {guest_path} but host never "
                f"saw {host_path}"
            )
        os.makedirs(os.path.dirname(dest_png) or ".", exist_ok=True)
        shutil.move(host_path, dest_png)

    def read_guest_file(self, guest_path: str, host_dest: str) -> bool:
        """Copy a small file out of the guest via the writable shared dir."""
        guest_share_dir = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}"
        guest_filename = (
            f"file-{int(time.time() * 1000)}-"
            f"{os.path.basename(guest_path)}"
        )
        guest_dest = f"{guest_share_dir}/{guest_filename}"
        proc = self.ssh(
            f"cp {shlex.quote(guest_path)} {shlex.quote(guest_dest)} && sync",
            check=False, timeout=30,
        )
        if proc.returncode != 0:
            return False
        host_src = os.path.join(self.host_output_dir, guest_filename)
        for _ in range(40):
            if os.path.isfile(host_src) and os.path.getsize(host_src) > 0:
                break
            time.sleep(0.25)
        if not os.path.isfile(host_src):
            return False
        os.makedirs(os.path.dirname(host_dest) or ".", exist_ok=True)
        shutil.move(host_src, host_dest)
        return True

    @property
    def guest_shared_output_dir(self) -> str:
        """Path of the writable shared dir inside the guest."""
        return f"{GUEST_SHARED_ROOT}/{SHARE_OUT}"


def run_interactive_setup(vm: "TartVM") -> None:
    """One-time setup flow: boot the VM with a host-side window so the
    user can click "Allow" on the persistent TCC dialogs (the
    sshd-session screen-capture bypass prompt and Roam's local-network
    permission). The grants land on the VM disk and survive subsequent
    `tart stop`/`tart run --no-graphics` cycles, so this only has to
    happen once per fresh `tart clone`.

    Caller must construct the VM with host_app_dir/host_output_dir
    pointing at real directories; `install_roam_app` runs as part of
    setup so the local-network dialog can be triggered."""
    print()
    print("=" * 72)
    print("Tart VM interactive TCC-grant setup")
    print("=" * 72)
    print(
        "A host window will open showing the guest macOS desktop.\n"
        "This script will ask the guest to do two things - please click\n"
        "'Allow' on each dialog when it appears inside the VM window:\n"
        "  1. Screen recording bypass for `com.apple.sshd-session`\n"
        "  2. Local-network access for `Roam`\n"
        "Once both are granted they persist on the VM disk for all\n"
        "future headless runs."
    )
    print("=" * 72)
    print()

    vm.bring_up(headless=False)
    vm.ensure_guest_display()
    vm.install_roam_app()

    print()
    print(
        "Note: TCC grants (screen recording + accessibility) are now written\n"
        "directly to the guest's TCC.db during install, so the dialogs below\n"
        "may not even appear. This interactive flow remains as a fallback -\n"
        "if no dialog shows, just press Enter to continue."
    )
    print()
    print(">>> Step 1: triggering the screen recording bypass dialog ...")
    print(
        "    A TCC dialog requesting the screen-capture 'private window\n"
        "    picker' bypass will appear inside the VM window. Click 'Allow'.\n"
        "    This grant covers the exact same launchctl-asuser code path the\n"
        "    real capture runs use, so all subsequent runs stay clean."
    )
    capture_target = f"{GUEST_SHARED_ROOT}/{SHARE_OUT}/setup-trigger.png"
    # Fire-and-forget - we don't care about the result; we only need the
    # TCC dialog to appear so the user can grant. The capture itself may
    # produce an unusable image while the dialog is up.
    vm.screencapture(["-x", "-t", "png", capture_target])
    input("\n    Press Enter once you've clicked 'Allow' on the dialog ... ")

    print()
    print(">>> Step 2: triggering Roam's local-network permission dialog ...")
    print(
        "    Roam will launch inside the VM with the screenshot-test data,\n"
        "    and macOS will show a dialog: 'Allow \"Roam\" to find devices\n"
        "    on local networks?'. Click 'Allow'."
    )
    vm.launch_roam([
        "-DataTesting", "-DataLoadTestingData", "-ScreenshotTesting",
    ])
    input("\n    Press Enter once you've clicked 'Allow' on the dialog ... ")
    vm.kill_roam()

    print()
    print(">>> Setup complete. Stopping VM (state persists on disk).")
    vm.stop()
    print()
    print(
        "From now on, regular `python sync-metadata.py --platform macOS "
        "--sync-screenshots` runs will use the granted permissions and "
        "capture cleanly without dialogs over the app."
    )


def build_roam_app() -> str:
    """Build the macOS Debug Roam.app on the host and return its path.

    `ENABLE_DEBUG_DYLIB=NO` builds a single-binary app instead of the
    Xcode 16 default that splits a `Roam.debug.dylib` out of the main
    executable. The split form fails `codesign --force --deep` ad-hoc
    re-signing in the guest ("main executable failed strict validation"),
    which is required because virtio-fs traversal strips the host's
    signature. Disabling it keeps the in-guest re-sign valid."""
    print("[tart] building Roam (macOS Debug) on host ...")
    # xcbeautify is optional - fall back to raw output if absent.
    pipe_cmd = "xcbeautify" if shutil.which("xcbeautify") else "cat"
    subprocess.run(
        f"set -o pipefail && "
        f"xcodebuild build "
        f"-scheme Roam "
        # Pin to arm64 explicitly. Plain `platform=macOS` matches this Mac
        # twice - once per arch slice (arm64 + x86_64) - so xcodebuild warns
        # "Using the first of multiple matching destinations". `arch=arm64`
        # disambiguates to a single destination (silencing the warning) and
        # keeps the build a thin arm64 binary - all the Apple-Silicon guest
        # needs. (`generic/platform=macOS` also silences it but builds a
        # heavier x86_64+arm64 universal binary.)
        f"-destination 'platform=macOS,arch=arm64' "
        f"-configuration Debug "
        f"ENABLE_DEBUG_DYLIB=NO "
        f"-quiet | {pipe_cmd}",
        shell=True, check=True,
    )
    derived = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    candidates: list[str] = []
    if os.path.isdir(derived):
        for entry in os.listdir(derived):
            if entry.startswith("Roam-"):
                candidate = os.path.join(
                    derived, entry, "Build", "Products", "Debug", "Roam.app"
                )
                if os.path.isdir(candidate):
                    candidates.append(candidate)
    if not candidates:
        raise RuntimeError(
            "Built Roam.app not found under DerivedData. Check that the "
            "xcodebuild invocation produced a Debug macOS build."
        )
    app_path = max(candidates, key=os.path.getmtime)

    # Zip the bundle next to itself (preserving the embedded code
    # signature). The guest extracts this single file rather than the
    # bundle directory: copying Roam.app through a virtio-fs directory
    # share rewrites per-file metadata and invalidates `_CodeSignature/
    # CodeResources` ("invalid resource directory"), whereas a single zip
    # is copied byte-for-byte and extracts to a bundle whose resource
    # signature is intact.
    zip_path = os.path.join(os.path.dirname(app_path), GUEST_APP_ZIP_NAME)
    print(f"[tart] zipping Roam.app -> {zip_path}")
    if os.path.exists(zip_path):
        os.remove(zip_path)
    subprocess.run(
        ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
         app_path, zip_path],
        check=True,
    )
    return app_path
