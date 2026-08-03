#!/usr/bin/env python3

import re
import subprocess
from datetime import datetime
import argparse
import os
import shutil
import tempfile
import uuid
from typing import Tuple
import urllib.error
import urllib.request

# 1. Before running, make sure you create an API key from App Store Connect
#     (App Store Connect -> Users and Access -> Integrations -> App Store Connect API) and store the downloaded key in ~/.private_keys
# 2. Then set the following environment variables:
#     XCODE_API_KEY="API_KEY_ID"
#     XCODE_API_ISSUER="API_ISSUER_ID"
#
#     Find both of these values in App Store Connect web after creating the API key
#
# Which key to use (verified 2026-07-22): use XCODE_API_KEY=ZWF866Z497 with
# XCODE_API_ISSUER=cbcdbb0a-aae2-46de-af95-4700664fad72. It is the only key in
# ~/.private_keys with App Store Connect distribution access. The others fail:
#   - V7DX9R58N2 -> "Cloud signing permission error" / no "iOS Distribution" certificate
#   - 834ACPS85P -> "Unauthenticated" / "No Accounts with App Store Connect Access"
#   - PBG7VN88T9 -> "Unauthenticated" / "No Accounts with App Store Connect Access"
# The two Unauthenticated keys likely belong to a different issuer than the one above.


# Where BACKEND_API_KEY may live, in priority order. Secrets.xcconfig is the
# only one Xcode reads; the rest are sources we can populate it from so that a
# local archive stops depending on a gitignored file being present by luck.
BACKEND_API_KEY_SOURCES = ("Secrets.xcconfig", ".env", "backend/.env")


def ensure_backend_api_key():
    """Guarantee Secrets.xcconfig exists with a real key before archiving.

    Vars.xcconfig pulls it in with `#include?`, so a missing file is silent:
    `$(BACKEND_API_KEY)` in Roam/Info.plist expands to the empty string, the
    build succeeds, and the shipped app sends `x-api-key: ` on every backend
    call -- which the server answers with 401. That is how 1.49 and 1.50 went
    out with a dead developer chat.

    CI writes Secrets.xcconfig from a repo secret. Locally the same value is
    already sitting in backend/.env, so copy it across rather than making the
    developer remember to hand-create a file they cannot commit.
    """
    if load_dotenv("Secrets.xcconfig").get("BACKEND_API_KEY"):
        return

    for source in BACKEND_API_KEY_SOURCES:
        key = os.environ.get("BACKEND_API_KEY") or load_dotenv(source).get(
            "BACKEND_API_KEY"
        )
        if key:
            with open("Secrets.xcconfig", "w") as file:
                file.write(f"BACKEND_API_KEY = {key}\n")
            print(f"Wrote Secrets.xcconfig from {source}")
            return

    raise SystemExit(
        "BACKEND_API_KEY is missing or empty.\n"
        "Vars.xcconfig includes Secrets.xcconfig optionally, so without it the "
        "app ships with an empty key and every backend request 401s.\n"
        "Set $BACKEND_API_KEY, or add it to one of: "
        + ", ".join(BACKEND_API_KEY_SOURCES)
    )


def verify_archived_api_key(platform: str, archive_path: str):
    """Read the key back out of the artifact that was actually built.

    The pre-flight check proves the file exists; this proves the value made it
    through Vars.xcconfig into the app's Info.plist. It catches the failure
    modes a file check cannot: a renamed variable, a target whose build
    configuration lost its baseConfigurationReference, a stale build dir.
    """
    import glob

    candidates = glob.glob(f"{archive_path}/Products/Applications/*.app/Info.plist")
    candidates += glob.glob(
        f"{archive_path}/Products/Applications/*.app/Contents/Info.plist"
    )
    if not candidates:
        raise SystemExit(f"No app Info.plist found in {archive_path}")

    for plist in candidates:
        value = subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", "Print :BACKEND_API_KEY", plist],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if not value:
            raise SystemExit(
                f"{platform}: BACKEND_API_KEY is empty in {plist}.\n"
                "The archive would ship with a dead backend connection "
                "(developer chat, diagnostics upload). Refusing to continue."
            )
    print(f"BACKEND_API_KEY present in the {platform} archive")


def archive_application(platform: str, render_github_actions: bool = False):
    scheme = "Roam"
    project_path = "."
    archive_path = f"{project_path}/Archives/XCArchives/{platform}.xcarchive"
    # First remove directory and all its contents
    subprocess.run(f'rm -rf "{archive_path}"', shell=True)
    print(f"Archiving application for platform {platform}")
    subprocess.run(
        f"""set -o pipefail && xcodebuild archive -project "{project_path}/Roam.xcodeproj" -scheme "{scheme}" -archivePath "{archive_path}" -destination 'generic/platform={platform}'{authentication_args()} | xcbeautify{' --renderer github-actions' if render_github_actions else ''}""",
        shell=True,
        check=True,
    )
    verify_archived_api_key(platform, archive_path)
    print(f"Archive succeeded for platform {platform}")


def authentication_args() -> str:
    """App Store Connect credentials plus -allowProvisioningUpdates.

    The archive needs these as much as the export does: every target signs
    automatically, so on a machine that has never built Roam there are no
    profiles on disk and Xcode has to mint them. Without the flag it fails with
    "No profiles for 'com.msdrigg.roam.…' were found ... Automatic signing is
    disabled and unable to generate a profile."
    """
    api_key = os.environ.get("XCODE_API_KEY")
    api_issuer = os.environ.get("XCODE_API_ISSUER")
    if not api_key or not api_issuer:
        return ""
    key_path = os.path.expanduser(f"~/.private_keys/AuthKey_{api_key}.p8")
    return (
        f" -authenticationKeyID {api_key}"
        f" -authenticationKeyIssuerID {api_issuer}"
        f" -authenticationKeyPath {key_path}"
        f" -allowProvisioningUpdates"
    )


def publish_to_app_store(platform: str, render_github_actions: bool = False):
    print(f"Exporting for platform {platform}")
    auth_args = authentication_args()
    subprocess.run(
        f"""set -o pipefail && xcodebuild -exportArchive -archivePath "./Archives/XCArchives/{platform}.xcarchive" -exportPath "./Archives/Exports/{platform}" -exportOptionsPlist ./scripts/options.plist{auth_args} | xcbeautify{' --renderer github-actions' if render_github_actions else ''}""",
        shell=True,
        check=True,
    )

    print(f"Publish succeeded for platform {platform}")


def load_dotenv(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    if not os.path.exists(path):
        return values

    with open(path, "r") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            values[key] = value

    return values


def resolve_required_config(
    name: str,
    cli_value: str | None,
    dotenv_values: dict[str, str],
) -> str:
    value = cli_value or os.environ.get(name) or dotenv_values.get(name)
    if not value:
        raise ValueError(
            f"{name} is required. Pass --{name.lower().replace('_', '-')} or add {name}=... to .env"
        )
    return value


class MultipartBody:
    """Concatenates the multipart prefix, the zip file, and the closing boundary
    into one readable stream. `http.client` reads request bodies in 8 KB blocks
    when the object exposes `read`, so nothing larger than that is ever held in
    memory on either end of the upload."""

    def __init__(self, prefix: bytes, file, suffix: bytes):
        self._parts = [prefix, file, suffix]
        self._index = 0

    def read(self, size: int = -1) -> bytes:
        while self._index < len(self._parts):
            part = self._parts[self._index]
            if isinstance(part, bytes):
                if size is None or size < 0:
                    self._index += 1
                    if part:
                        return part
                    continue
                chunk, remainder = part[:size], part[size:]
                self._parts[self._index] = remainder
                if chunk:
                    return chunk
                self._index += 1
                continue

            chunk = part.read(size)
            if chunk:
                return chunk
            self._index += 1
        return b""


def upload_dsyms(
    platform: str,
    backend_url: str,
    backend_api_key: str,
    bundle_identifier: str,
):
    archive_path = f"./Archives/XCArchives/{platform}.xcarchive"
    dsym_dir = f"{archive_path}/dSYMs"
    if not os.path.isdir(dsym_dir):
        raise FileNotFoundError(f"No dSYMs directory found at {dsym_dir}")

    app_version, build_version = get_current_versions()
    backend_url = backend_url.rstrip("/")

    print(
        f"Uploading dSYMs for {platform} {bundle_identifier} {app_version} ({build_version})"
    )
    with tempfile.TemporaryDirectory() as tmp:
        zip_base = os.path.join(tmp, f"{platform}-dSYMs")
        zip_path = shutil.make_archive(zip_base, "zip", root_dir=archive_path, base_dir="dSYMs")

        # Streamed as multipart/form-data rather than base64 in a JSON body. The
        # zip runs to hundreds of MB and buffering it (plus its base64 inflation)
        # OOM-killed the 256 MB Fly machine.
        boundary = f"----RoamDsymUpload{uuid.uuid4().hex}"
        fields = {
            "bundleIdentifier": bundle_identifier,
            "appVersion": app_version,
            "buildVersion": build_version,
            "platform": platform,
        }

        prefix = b""
        for name, value in fields.items():
            prefix += (
                f"--{boundary}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
                f"{value}\r\n"
            ).encode("utf-8")
        prefix += (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="dsymZip"; filename="{platform}-dSYMs.zip"\r\n'
            f"Content-Type: application/zip\r\n\r\n"
        ).encode("utf-8")
        suffix = f"\r\n--{boundary}--\r\n".encode("utf-8")

        zip_size = os.path.getsize(zip_path)
        content_length = len(prefix) + zip_size + len(suffix)
        print(f"  zip is {zip_size / (1024 * 1024):.1f} MB, streaming multipart upload")

        with open(zip_path, "rb") as file:
            body = MultipartBody(prefix, file, suffix)
            request = urllib.request.Request(
                f"{backend_url}/v2/upload-roam-dsym",
                data=body,
                headers={
                    "Content-Type": f"multipart/form-data; boundary={boundary}",
                    "Content-Length": str(content_length),
                    "x-api-key": backend_api_key,
                },
                method="POST",
            )

            try:
                with urllib.request.urlopen(request, timeout=900) as response:
                    response_body = response.read().decode("utf-8")
                    print(f"dSYM upload succeeded for {platform}: {response_body}")
            except urllib.error.HTTPError as error:
                response_body = error.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"dSYM upload failed for {platform}: HTTP {error.code} {response_body}"
                ) from error


def try_upload_dsyms(
    platform: str,
    backend_url: str,
    backend_api_key: str,
    bundle_identifier: str,
    render_github_actions: bool = False,
) -> bool:
    """Upload symbols without letting a failure block distribution.

    Publishing and symbol upload are interleaved per platform, so raising here
    stops every *later* platform from being published at all: one HTTP 502 on
    the iOS dSYM upload left macOS and visionOS unshipped. Symbols can be
    re-uploaded at any time with `--upload-dsyms`; a half-published release
    cannot be undone.
    """
    try:
        upload_dsyms(platform, backend_url, backend_api_key, bundle_identifier)
        return True
    except Exception as error:
        # ::warning:: surfaces in the Actions summary instead of scrolling past
        # in the log, so a skipped symbol upload stays visible on a green run.
        prefix = "::warning::" if render_github_actions else "WARNING: "
        print(f"{prefix}dSYM upload failed for {platform}, continuing: {error}")
        return False


def get_current_versions() -> Tuple[str, str]:
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    with open(project_file_path, "r") as file:
        project_contents = file.readlines()

    # Any dotted numeric version, not just two components: `git describe` will
    # hand back a three-component tag sooner or later, bump_versions() will
    # happily write `MARKETING_VERSION = 1.50.1;`, and a two-component-only
    # pattern would then fail to read back what it just wrote.
    marketing_version_line = [
        line
        for line in project_contents
        if re.search(r"MARKETING_VERSION = \d+(\.\d+)*;", line)
    ]

    current_version_line = [
        line
        for line in project_contents
        if re.search(r"CURRENT_PROJECT_VERSION = \d+\.\w+\.\d+", line)
    ]

    if not marketing_version_line:
        raise ValueError("Could not find marketing version in project file")
    if not current_version_line:
        raise ValueError("Could not find current version in project file")

    current_marketing_version = (
        marketing_version_line[0].split("=")[1].strip().strip(";")
    )
    current_version = current_version_line[0].split("=")[1].strip().strip(";")

    return current_marketing_version, current_version


def get_marketing_version():
    git_tag = (
        subprocess.check_output(["git", "describe", "--tags", "--abbrev=0"])
        .decode("utf-8")
        .strip()
    )
    return git_tag.strip("v")


def get_git_build_number():
    last_commit_sha = (
        subprocess.check_output(["git", "rev-parse", "--short", "HEAD"])
        .decode("utf-8")
        .strip()
    )
    decimal_sha = int(last_commit_sha, 16)
    # Last 8 characters of the SHA
    return f"{decimal_sha}"[-7:]


def get_build_version():
    date_str = datetime.now().strftime("%Y%m%d")
    git_commit = get_git_build_number()

    _, build_version = get_current_versions()
    patch_version = 0
    if build_version.startswith(f"{date_str}.{git_commit}"):
        patch_version = int(build_version.split(".")[-1]) + 1

    return f"{date_str}.{git_commit}.{patch_version}"


def version_sort_key(version: str) -> Tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def bump_versions():
    project_file_path = "./Roam.xcodeproj/project.pbxproj"

    current_marketing_version, current_build_version = get_current_versions()
    new_marketing_version, new_build_version = (
        get_marketing_version(),
        get_build_version(),
    )

    # `git describe` only sees tags that were actually pushed, so a tag living
    # only on a developer's machine leaves CI a release behind -- and the sed
    # below will happily rewrite MARKETING_VERSION *downwards*. That is how a
    # 1.50 project archived and uploaded itself to App Store Connect as 1.49.
    if version_sort_key(new_marketing_version) < version_sort_key(
        current_marketing_version
    ):
        raise SystemExit(
            f"Refusing to downgrade MARKETING_VERSION "
            f"{current_marketing_version} -> {new_marketing_version}.\n"
            f"The newest tag reachable from HEAD is v{new_marketing_version}, but "
            f"the project is already at {current_marketing_version}. Push the "
            f"newer tag (git push origin v{current_marketing_version}) or tag the "
            "release you actually intend to ship."
        )

    sed_cmd_marketing_version = f"sed -i '' 's/MARKETING_VERSION = {current_marketing_version};/MARKETING_VERSION = {new_marketing_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_marketing_version, shell=True, check=True)

    sed_cmd_build_version = f"sed -i '' 's/CURRENT_PROJECT_VERSION = {current_build_version};/CURRENT_PROJECT_VERSION = {new_build_version};/g' {project_file_path}"
    subprocess.run(sed_cmd_build_version, shell=True, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Xcode exporting and publishing script"
    )

    parser.add_argument(
        "--archive",
        help="Build and archive the application",
        action="store_true",
    )

    parser.add_argument(
        "--publish",
        help="Publish the application to App Store Connect",
        action="store_true",
    )

    parser.add_argument(
        "--platform",
        help="Platform to build and publish",
        choices=["macOS", "iOS", "visionOS"],
        nargs="+",
    )

    parser.add_argument(
        "--github-actions",
        help="Render output for GitHub Actions",
        action="store_true",
    )
    parser.add_argument(
        "--no-bump",
        help="Don't update versions to match git",
        action="store_true",
    )
    parser.add_argument(
        "--upload-dsyms",
        help="Upload archived dSYMs to the Roam backend",
        action="store_true",
    )
    parser.add_argument(
        "--backend-url",
        help="Backend base URL. Falls back to BACKEND_URL in the environment or .env",
    )
    parser.add_argument(
        "--backend-api-key",
        help="Backend API key. Falls back to BACKEND_API_KEY in the environment or .env",
    )
    parser.add_argument(
        "--bundle-identifier",
        help="Bundle identifier to record with the dSYM upload",
        default="com.msdrigg.roam",
    )
    parser.add_argument(
        "--bump-versions",
        help="Update the marketing and build versions in the Xcode project to match git before building",
        action="store_true",
    )
    parser.add_argument(
        "--env-file",
        help="Path to the env file used for backend upload settings",
        default=".env",
    )

    args = parser.parse_args()

    if args.bump_versions:
        bump_versions()

    # Only an archive may renumber the project. Bumping on a bare --publish
    # rewrites project.pbxproj *after* the .xcarchive was built, so the upload
    # would carry one version while the binary inside it carries another --
    # and --upload-dsyms would file the symbols under the wrong build.
    if not args.no_bump and args.archive:
        bump_versions()

    if args.archive:
        ensure_backend_api_key()
        for platform in args.platform or []:
            archive_application(platform, render_github_actions=args.github_actions)

    backend_url = None
    backend_api_key = None
    dsym_failures: list[str] = []
    if args.upload_dsyms:
        dotenv_values = load_dotenv(args.env_file)
        try:
            backend_url = resolve_required_config(
                "BACKEND_URL", args.backend_url, dotenv_values
            )
            backend_api_key = resolve_required_config(
                "BACKEND_API_KEY", args.backend_api_key, dotenv_values
            )
        except ValueError as error:
            parser.error(str(error))

    if args.publish:
        # A bare --publish uploads an archive built by an earlier invocation,
        # which may predate the pre-flight check, so re-verify the artifact.
        for platform in args.platform or []:
            verify_archived_api_key(
                platform, f"./Archives/XCArchives/{platform}.xcarchive"
            )
        for platform in args.platform or []:
            publish_to_app_store(platform, render_github_actions=args.github_actions)
            if args.upload_dsyms and not try_upload_dsyms(
                platform,
                backend_url,
                backend_api_key,
                args.bundle_identifier,
                render_github_actions=args.github_actions,
            ):
                dsym_failures.append(platform)
    elif args.upload_dsyms:
        for platform in args.platform or []:
            if not try_upload_dsyms(
                platform,
                backend_url,
                backend_api_key,
                args.bundle_identifier,
                render_github_actions=args.github_actions,
            ):
                dsym_failures.append(platform)

    if dsym_failures:
        # Deliberately not an error: the builds are on App Store Connect, and
        # failing the run here would misreport a successful distribution.
        print(
            f"\nSymbols were NOT uploaded for: {', '.join(dsym_failures)}.\n"
            f"Re-run once the backend is healthy:\n"
            f"    ./scripts/export.py --upload-dsyms --no-bump --platform "
            f"{' '.join(dsym_failures)}"
        )
