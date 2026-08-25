//! Auto-review rules for symbolicated crash reports.
//!
//! When a symbolication completes, the rendered report is matched against
//! [`RULES`]. The first rule that matches wins: the backend posts its
//! explanation into the crash thread and marks the thread reviewed, attributed
//! to `auto:<rule id>`. Anything that matches no rule stays unreviewed and
//! shows up in `GET /v2/crashes/unreviewed` for a human.
//!
//! Rules are deliberately a compiled-in list rather than database rows: each
//! one encodes a diagnosis that was worked out by reading stacks, and its reply
//! text cites the fix that shipped alongside it. Adding a rule should be a code
//! review, not a config edit.
//!
//! Every rule also records the app version its fix shipped in, and a match is
//! tagged against the version the crash came from: a crash from before that
//! release is [`FixStatus::Fixed`] (the user needs to update), one from that
//! release or later is [`FixStatus::Unfixed`] — the same stack surviving the
//! fix, which is news — and a report with no readable version is
//! [`FixStatus::Unknown`].

use std::sync::LazyLock;

use regex::Regex;

/// Facts pulled out of a rendered symbolicated report, used for matching and
/// stored on the review row so the list endpoints can triage without
/// re-downloading attachments.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct CrashFacts {
    pub app_version: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    /// Termination code as lowercase hex with an `0x` prefix, e.g. `0x8badf00d`.
    pub termination_code: Option<String>,
    /// `Thermal Level:` out of the termination reason's `ThermalInfo` block.
    /// 0 is nominal; 9 is what the OS also labels `Thermal State: critical`.
    pub thermal_level: Option<i64>,
    /// The app's own share of the CPU over the watchdog window, from
    /// `Elapsed application CPU time (seconds): 0.127, 0% CPU`. Deliberately
    /// the *application* figure and not the `Elapsed total` one: the gap
    /// between them is what separates a starved process from a busy one.
    pub app_cpu_percent: Option<i64>,
}

/// Reads `  key: value` out of a rendered report's metadata block.
///
/// Runs a handful of times per crash, so it builds its regex per call rather
/// than carrying a cache.
fn metadata_value(report: &str, key: &str) -> Option<String> {
    let pattern = format!(r"(?m)^\s*{}: (.+)$", regex::escape(key));
    let regex = Regex::new(&pattern).ok()?;
    regex
        .captures(report)
        .map(|caps| caps[1].trim().to_string())
        .filter(|value| !value.is_empty())
}

/// Extract the `Code 0x...` value out of a termination reason line.
fn termination_code(report: &str) -> Option<String> {
    static RE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)code[: ]\s*0x([0-9a-f]+)").expect("valid code regex"));
    let reason = metadata_value(report, "terminationReason")
        .or_else(|| metadata_value(report, "Termination reason"))?;
    RE.captures(&reason)
        .map(|caps| format!("0x{}", caps[1].to_ascii_lowercase()))
}

/// Reads `Thermal Level:   9` out of the report.
///
/// Matched against the whole report rather than the metadata block: the
/// `ThermalInfo` list lives inside the multi-line `terminationReason` value, so
/// [`metadata_value`]'s per-line `key: value` shape does not reach it.
fn thermal_level(report: &str) -> Option<i64> {
    static RE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"Thermal Level:\s*(\d+)").expect("valid thermal regex"));
    RE.captures(report)?[1].parse().ok()
}

/// Reads the percentage off the `Elapsed application CPU time` line.
fn app_cpu_percent(report: &str) -> Option<i64> {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"Elapsed application CPU time \(seconds\): [\d.]+, (\d+)% CPU")
            .expect("valid app cpu regex")
    });
    RE.captures(report)?[1].parse().ok()
}

impl CrashFacts {
    pub fn from_report(report: &str) -> Self {
        Self {
            app_version: metadata_value(report, "appVersion"),
            device_type: metadata_value(report, "deviceType"),
            os_version: metadata_value(report, "osVersion"),
            exception_type: metadata_value(report, "exceptionType").and_then(|v| v.parse().ok()),
            signal: metadata_value(report, "signal").and_then(|v| v.parse().ok()),
            termination_code: termination_code(report),
            thermal_level: thermal_level(report),
            app_cpu_percent: app_cpu_percent(report),
        }
    }
}

/// Parses a dotted numeric version into comparable components.
///
/// Anything after the leading `[0-9.]` run is dropped, so `1.51 (204)` and
/// `1.51-beta` both read as `1.51`. Returns `None` when there is no numeric
/// component at all.
fn parse_version(version: &str) -> Option<Vec<u64>> {
    let numeric: String = version
        .trim()
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let parts: Vec<u64> = numeric
        .split('.')
        .filter(|part| !part.is_empty())
        .map(|part| part.parse().ok())
        .collect::<Option<_>>()?;
    (!parts.is_empty()).then_some(parts)
}

/// How a matched rule's fix relates to the version the crash came from.
///
/// Comparison is component-wise, so `1.50 < 1.51 < 1.51.1` — a plain string
/// compare would put `1.5` after `1.50`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FixStatus {
    /// The crash predates the release that fixed it: updating resolves it.
    Fixed,
    /// The crash is from the release that fixed it, or later. The fix did not
    /// hold, so this needs a human even though the stack is recognised.
    Unfixed,
    /// The rule describes something that is not a defect in the app, so there is
    /// no version to compare against. See [`CrashRule::environmental`].
    NotADefect,
    /// No usable `appVersion` on the report, or no fix version on the rule.
    Unknown,
}

/// A single auto-review rule. All specified conditions must hold.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashRule {
    pub id: &'static str,
    pub title: &'static str,
    /// App version that shipped this rule's fix, e.g. `"1.51"`. Crashes from
    /// this version onwards are tagged [`FixStatus::Unfixed`].
    pub fixed_in: Option<&'static str>,
    /// The kill is a property of the device or the OS, not a bug in the app, so
    /// there is nothing to fix and no version to compare against. Matching
    /// reports are tagged [`FixStatus::NotADefect`] and reviewed. Set this only
    /// where the report itself carries the evidence — a rule that merely *looks*
    /// environmental should stay in the manual queue.
    pub environmental: bool,
    /// Mach exception type, e.g. 10 for `EXC_CRASH`, 12 for `EXC_GUARD`.
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    /// Lowercase hex termination code, e.g. `0x8badf00d`.
    pub termination_code: Option<&'static str>,
    /// Minimum `Thermal Level:` on the report, inclusive. A report with no
    /// thermal figure does not match a rule that sets this.
    pub min_thermal_level: Option<i64>,
    /// Maximum `Elapsed application CPU time` percentage, inclusive. A report
    /// with no CPU figure does not match a rule that sets this. This is the
    /// app's own share, not the `Elapsed total` figure on the line above it,
    /// which covers the whole device.
    pub max_app_cpu_percent: Option<i64>,
    /// Substrings that must all appear somewhere in the report (stack frames).
    pub all_of: &'static [&'static str],
    /// Substrings that must not appear. Used to keep rules from overlapping.
    pub none_of: &'static [&'static str],
    /// Markdown posted into the thread when this rule matches.
    pub reply: &'static str,
}

impl CrashRule {
    pub fn matches(&self, report: &str, facts: &CrashFacts) -> bool {
        if let Some(expected) = self.exception_type {
            if facts.exception_type != Some(expected) {
                return false;
            }
        }
        if let Some(expected) = self.signal {
            if facts.signal != Some(expected) {
                return false;
            }
        }
        if let Some(expected) = self.termination_code {
            if facts.termination_code.as_deref() != Some(expected) {
                return false;
            }
        }
        if let Some(minimum) = self.min_thermal_level {
            if facts.thermal_level.is_none_or(|level| level < minimum) {
                return false;
            }
        }
        if let Some(maximum) = self.max_app_cpu_percent {
            if facts.app_cpu_percent.is_none_or(|share| share > maximum) {
                return false;
            }
        }
        if !self.all_of.iter().all(|needle| report.contains(needle)) {
            return false;
        }
        if self.none_of.iter().any(|needle| report.contains(needle)) {
            return false;
        }
        true
    }

    /// Places the crash's app version against the release that fixed this rule.
    pub fn fix_status(&self, facts: &CrashFacts) -> FixStatus {
        if self.environmental {
            return FixStatus::NotADefect;
        }
        let Some(fixed_in) = self.fixed_in.and_then(parse_version) else {
            return FixStatus::Unknown;
        };
        let Some(crashed_on) = facts.app_version.as_deref().and_then(parse_version) else {
            return FixStatus::Unknown;
        };
        if crashed_on < fixed_in {
            FixStatus::Fixed
        } else {
            FixStatus::Unfixed
        }
    }
}

/// A rule matched against one crash, together with where that crash sits
/// relative to the rule's fix.
#[derive(Debug, Clone, Copy)]
pub struct RuleMatch {
    pub rule: &'static CrashRule,
    pub status: FixStatus,
}

impl RuleMatch {
    /// The markdown to post in-thread: the rule's diagnosis, then a line
    /// placing this particular crash against the fix.
    pub fn reply(&self, facts: &CrashFacts) -> String {
        let fixed_in = self.rule.fixed_in.unwrap_or("a later release");
        let verdict = match self.status {
            FixStatus::Fixed => format!(
                ":white_check_mark: **Fixed in {fixed_in}.** This report is from {}, which predates the fix — updating to {fixed_in} or later resolves it.",
                facts.app_version.as_deref().unwrap_or("an earlier version"),
            ),
            FixStatus::Unfixed => format!(
                ":rotating_light: **UNFIXED.** The fix above shipped in {fixed_in}, and this report is from {} — the crash survived it. Left unreviewed for a human.",
                facts.app_version.as_deref().unwrap_or("that release or later"),
            ),
            FixStatus::NotADefect => ":thermometer: **Nothing to fix in the app.** The report itself carries the evidence that the system, not Roam, ended the process — see above. Reviewed automatically; reopen the thread if you disagree.".to_string(),
            FixStatus::Unknown => match self.rule.fixed_in {
                Some(version) => format!(
                    ":grey_question: **Fix status unknown.** The fix shipped in {version}, but this report carries no readable `appVersion`, so whether it predates the fix is unclear."
                ),
                None => ":grey_question: **Fix status unknown.** No fix version is recorded for this rule.".to_string(),
            },
        };
        format!(
            "{}\n\n{verdict}\n\n_Matched automatically by rule `{}`._",
            self.rule.reply, self.rule.id
        )
    }

    /// One line for the review row, so the triage list carries the tag without
    /// anyone opening the thread.
    pub fn review_note(&self, facts: &CrashFacts) -> String {
        let title = self.rule.title;
        match (self.status, self.rule.fixed_in) {
            (FixStatus::Fixed, Some(fixed_in)) => format!("{title} (fixed in {fixed_in})"),
            (FixStatus::Unfixed, Some(fixed_in)) => format!(
                "UNFIXED — still crashing on {} after the {fixed_in} fix: {title}",
                facts.app_version.as_deref().unwrap_or("a later version"),
            ),
            (FixStatus::NotADefect, _) => format!("{title} (not an app defect)"),
            _ => format!("{title} (fix status unknown)"),
        }
    }
}

/// Returns the first rule matching the report, if any.
pub fn match_rule(report: &str, facts: &CrashFacts) -> Option<RuleMatch> {
    RULES
        .iter()
        .find(|rule| rule.matches(report, facts))
        .map(|rule| RuleMatch {
            rule,
            status: rule.fix_status(facts),
        })
}

const DEAD10CC_REPLY: &str = ":ninja: **Auto-review: `0xdead10cc` — suspended while holding the database lock**

`EXC_CRASH (10)` / `SIGKILL (9)` with the attributed thread in the middle of a database write. This is not a fault in the app's own code — iOS killed the process deliberately.

Persistent writes hold an exclusive `flock` on a lock file in the shared app-group container, on top of the SQLite/WAL locks on `Roam.sqlite` beside it. A suspended process still holding those can block the widget extension indefinitely, so the system terminates it.

**Known cause, fix:**
- a background-task assertion is held across every persistent write, so the process stays alive long enough to commit and release the lock
- the file lock covers the transaction only — it used to be held across a full snapshot reload that scans every table
- automatic device discovery stops when the app is backgrounded, removing the main source of writes still in flight at suspension time";

const EXC_GUARD_REPLY: &str = ":ninja: **Auto-review: `EXC_GUARD` — the SSDP socket was closed twice**

`EXC_GUARD (12)`, attributed to `close()` inside the `defer` in `scanDevicesContinually`.

That function closed its UDP socket in two places: the `onCancel` handler of `withTaskCancellationHandler` (which is what interrupts the blocking `receiveFrom`), and the body's own `defer` as it unwinds. On cancellation both run, so `close(2)` fires twice on the same descriptor. By the second call the kernel has usually reused that number, and when the new owner is a *guarded* descriptor — GRDB's SQLite handles and Network.framework both guard theirs — the process is killed on the spot.

`try? socket.close()` cannot defend against this: `EXC_GUARD` is a Mach exception, not an `errno`.

**Known cause, fix:** both paths now go through a close-once wrapper, so the descriptor reaches `close(2)` exactly once regardless of which path wins the race.";

const SCENE_PHASE_REENTRANCY_REPLY: &str = ":ninja: **Auto-review: stack overflow — `forceFront` re-entered the SwiftUI update it was called from**

`EXC_BAD_ACCESS (1)` / `SIGSEGV (11)` with the faulting address inside the **Stack Guard** region below the main thread's stack: the main thread ran off the end of its stack. Not a dangling pointer — unbounded recursion.

The cycle is visible in the attributed thread, `AppGraph.graphDidChange` alternating with `AppDelegate.scenesDidChange` all the way down:

`NSApplication.forceFront` called `makeKeyAndOrderFront` synchronously from a SwiftUI action, so it ran inside `Update.dispatchActions` — still nested in the update pass that queued it. `makeKeyAndOrderFront` posts `NSWindowDidOrderOnScreen` from there, SwiftUI turns that into a scene-phase change, and `AppGraph.graphDidChange` re-enters the update it is already inside. Every level re-evaluates the scene bodies, which runs the action again.

Launch-time window restoration is what makes it fatal rather than merely wasteful: `NSPersistentUIRestorer` is ordering windows on screen while the app graph is still settling, so the cycle never reaches a quiet state and the stack runs out first.

**Known cause, fix:** `forceFront` now defers to the next runloop turn, so the in-flight update finishes before `makeKeyAndOrderFront` fires and the notification lands on a quiet graph.";

const MENU_BAR_EXTRA_REENTRANCY_REPLY: &str = ":ninja: **Auto-review: stack overflow — `MenuBarExtra(isInserted:)` re-entered the SwiftUI update pass**

`EXC_BAD_ACCESS (1)` / `SIGSEGV (11)` with the faulting address inside the **Stack Guard** region below the main thread's stack: the main thread ran off the end of its stack. Not a dangling pointer — unbounded recursion.

MetricKit cannot unwind an overflowed stack, so the attributed thread shows only whatever the Swift runtime was demangling when the last frame would not fit. Read the in-process backtrace instead: it holds `AppGraph.graphDidChange` alternating with `AppDelegate.scenesDidChange` all the way down, with `MenuBarExtra(isInserted:)` inside the cycle.

Same recursion as `scene-phase-reentrancy-stack-overflow`, driven from a different place. `MenuBarExtra` writes back through its `isInserted` binding while SwiftUI reconciles the scene, and `@AppStorage` forwards even a same-value write to `UserDefaults`. That write posts `didChangeNotification`, which invalidates the body that produced the scene, so `graphDidChange` re-enters the update it is already inside — and every level reconciles `MenuBarExtra` again.

**Known cause, fix:** the `isInserted` binding now drops echoes — a write matching the value already stored is not forwarded to `UserDefaults`, so reconciliation no longer dirties the graph it is running inside. Real toggles still write through.";

const WATCHDOG_REPLY: &str = ":ninja: **Auto-review: `0x8BADF00D` watchdog — main thread blocked cancelling the Bonjour browser**

The termination reason pins this down: the process failed to terminate within its 5 second budget.

The attributed thread is the **main thread**, parked in `nw_browser_cancel`, reached from `requestLocalNetworkAuthorization`'s `onCancel` handler.

`onCancel` runs synchronously on whichever thread cancels the task, and SwiftUI cancels `.task` work on the main thread while it applies a scene-phase change. `NWBrowser.cancel()` and `NWListener.cancel()` block on an internal Network.framework lock, so when the network queue is busy the main thread stalls past the termination budget and the watchdog kills the app.

**Known cause, fix:** listener/browser teardown is dispatched onto the queue those objects already run on, so the cancelling thread is never blocked.";

const AUDIO_PLAYER_NODE_EXCEPTION_REPLY: &str = ":ninja: **Auto-review: `SIGABRT` — AVFAudio raised on `play()` against a stale output format**

`EXC_CRASH (10)` / `SIGABRT (6)`, and the attributed thread shows why: `objc_exception_throw` out of `-[AVAudioPlayerNode play]`, through `objc_terminate`, into `abort`. An Objective-C exception, not a signal in Roam's own code.

Swift cannot catch those. AVFoundation reports misuse by raising rather than returning an error, and an unhandled raise ends the process immediately — `try` around the call does nothing.

`AudioPlayer` built its engine connections and its `AVAudioConverter` once, in `init`, against the output device's format at that moment. On iOS a route change tears the session down and `handleRouteChange` rebuilds it, but macOS had no equivalent observer: the user switches default output device, the next `start()` succeeds against the new one, and the player node is still connected with the *old* device's format. `play()` raises on the mismatch.

The `guard engine.isRunning` ahead of it did not help — the engine really was running. It was the graph below it that was stale.

**Known cause, fix:** the graph and converter are now re-derived from the current output format on every `start()`, and a device reporting no usable format is rejected with a thrown error rather than left for AVFAudio to raise on. The `play()` and `scheduleBuffer` calls additionally run under an Objective-C exception trap, so a raise that still slips through surfaces as a Swift error instead of killing the process.";

const LOCAL_NETWORK_CANCEL_RACE_REPLY: &str = ":ninja: **Auto-review: `SIGSEGV` — two threads cancelled the Bonjour browser at once**

`EXC_BAD_ACCESS (1)` / `SIGSEGV (11)` on a near-null address inside `nw_browser_cancel`, attributed to `requestLocalNetworkAuthorization`.

Not the `0x8BADF00D` watchdog kill that `local-network-cancel-watchdog` describes — that one is a *stall* on the main thread and carries a termination reason. This is a **use-after-free**: `NWBrowser.cancel()` is not safe to call concurrently with itself, and the fix for the watchdog left two paths that could both reach it — the task thread tearing the endpoints down as `requestLocalNetworkAuthorization` returned, and the `onCancel` handler firing when SwiftUI cancelled the `.task`. The `didResume` guard that was supposed to make the second call a no-op was checked outside the lock, so both callers passed it and Network.framework freed the browser twice.

**Known cause, fix:** teardown now goes through a claim-once `CancelOnceEndpoints` wrapper that takes the cancel under an `OSAllocatedUnfairLock`, so exactly one caller reaches `cancel()` no matter which path wins. The resume is claimed the same way. Both still run on the browser's own queue, so the watchdog fix is preserved.";

const THERMAL_STARVATION_REPLY: &str = ":ninja: **Auto-review: `0x8BADF00D` watchdog — the device was overheating, not the app**

`EXC_CRASH (10)` / `SIGKILL (9)` with a watchdog termination reason, but the numbers in that reason rule the app out as the cause:

- **`Thermal State: critical`** (thermal level 9) — the highest tier iOS reports. At that point the system is aggressively throttling every process on the device.
- **`Elapsed application CPU time: 0% CPU`** — Roam got a rounding error's worth of CPU across the whole watchdog window, while the device as a whole stayed busy. The process was not doing slow work; it was not being scheduled.

A scene-update deadline is wall-clock, not CPU-time, so a process that never gets scheduled blows through it without ever running. The attributed thread is whatever the app happened to be parked in when the clock ran out, and reading it will mislead you.

**Nothing to fix:** this resolves when the device cools down. Common causes are charging in direct sun, a heavy game or export running in the foreground, or a stuck background process elsewhere on the system.";

/// Ordered: the first match wins, so put narrower rules first.
pub static RULES: &[CrashRule] = &[
    CrashRule {
        id: "scene-phase-reentrancy-stack-overflow",
        title: "Stack overflow from forceFront re-entering the SwiftUI update pass",
        // The deferral shipped in a re-cut 1.52 build, after the first 1.52
        // builds were already on App Store Connect. Version comparison is
        // marketing-version only, so a crash from an early 1.52 build reads as
        // UNFIXED and lands in the manual queue. That is the safe direction --
        // check `appBuildVersion` on the report before concluding the fix broke.
        fixed_in: Some("1.52"),
        environmental: false,
        exception_type: Some(1),
        signal: Some(11),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // The app frame alone would be too loose -- `forceFront` appears on any
        // stack that brings a window forward. It is the recursion above it that
        // makes this the bug, so require the SwiftUI half of the cycle too.
        all_of: &[
            "NSApplication.forceFront",
            "AppGraph.graphDidChange",
            "Stack Guard",
        ],
        none_of: &[],
        reply: SCENE_PHASE_REENTRANCY_REPLY,
    },
    // After the forceFront rule, and explicitly excluding it: both are the same
    // graphDidChange/scenesDidChange recursion, and a report carrying both
    // triggers belongs to the narrower one above.
    CrashRule {
        id: "menu-bar-extra-reentrancy-stack-overflow",
        title: "Stack overflow from MenuBarExtra(isInserted:) re-entering the SwiftUI update pass",
        fixed_in: Some("1.54"),
        environmental: false,
        exception_type: Some(1),
        signal: Some(11),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // `MenuBarExtra` and `isInserted` both appear inside the mangled
        // SwiftUI initialiser symbols, so plain substrings reach them without
        // depending on demangling. As with the forceFront rule, the scene frame
        // alone is too loose -- require the recursion and the Stack Guard hit.
        all_of: &[
            "MenuBarExtra",
            "isInserted",
            "AppGraph.graphDidChange",
            "Stack Guard",
        ],
        none_of: &["NSApplication.forceFront"],
        reply: MENU_BAR_EXTRA_REENTRANCY_REPLY,
    },
    CrashRule {
        id: "local-network-cancel-watchdog",
        title: "0x8BADF00D watchdog cancelling NWBrowser on the main thread",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: None,
        signal: None,
        termination_code: Some("0x8badf00d"),
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["nw_browser_cancel"],
        none_of: &[],
        reply: WATCHDOG_REPLY,
    },
    // Directly after the watchdog rule it is most likely to be confused with.
    // The two cannot collide -- that one needs a 0x8BADF00D termination code and
    // this one a SIGSEGV -- but they share `nw_browser_cancel`, so keep them
    // adjacent for whoever reads this list next.
    CrashRule {
        id: "local-network-cancel-race",
        title: "SIGSEGV from concurrent NWBrowser.cancel() in the local network check",
        fixed_in: Some("1.54"),
        environmental: false,
        exception_type: Some(1),
        signal: Some(11),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // The app frame matters here: `nw_browser_cancel` on its own would also
        // claim a crash in any other browser Roam cancels.
        all_of: &["nw_browser_cancel", "requestLocalNetworkAuthorization"],
        none_of: &[],
        reply: LOCAL_NETWORK_CANCEL_RACE_REPLY,
    },
    // EXC_CRASH/SIGABRT, so it cannot collide with the two EXC_CRASH/SIGKILL
    // rules below; the exception pair alone separates them.
    CrashRule {
        id: "audio-player-node-play-exception",
        title: "SIGABRT from AVAudioPlayerNode.play() raising on a stale output format",
        fixed_in: Some("1.54"),
        environmental: false,
        exception_type: Some(10),
        signal: Some(6),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // The ObjC throw plus both ends of the call: AVFAudio raising, and Roam
        // being the one that called it. `AVAudioPlayerNode` on its own would
        // also claim an unrelated abort that merely had audio on some thread.
        all_of: &[
            "objc_exception_throw",
            "AVAudioPlayerNode",
            "AudioPlayer.start",
        ],
        none_of: &[],
        reply: AUDIO_PLAYER_NODE_EXCEPTION_REPLY,
    },
    CrashRule {
        id: "ssdp-socket-double-close",
        title: "EXC_GUARD from double-closing the SSDP socket",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: Some(12),
        signal: None,
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["scanDevicesContinually", "FileDescriptor._close"],
        none_of: &[],
        reply: EXC_GUARD_REPLY,
    },
    CrashRule {
        id: "database-lock-suspension",
        title: "0xdead10cc suspension while holding the database file lock",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: Some(10),
        signal: Some(9),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["DatabaseFileLock.withExclusiveLock"],
        none_of: &[],
        reply: DEAD10CC_REPLY,
    },
    // Last on purpose. This is the broadest rule in the list -- it names no app
    // frame at all -- so every rule that recognises a *stack* gets first refusal.
    // A main thread genuinely deadlocked in Roam's own code also reports 0% app
    // CPU, and the only thing separating it from this is the thermal figure.
    CrashRule {
        id: "thermal-starvation-watchdog",
        title: "0x8BADF00D watchdog while the device was thermally throttled",
        fixed_in: None,
        environmental: true,
        exception_type: Some(10),
        signal: Some(9),
        termination_code: Some("0x8badf00d"),
        // Level 9 is the top of the scale, reported alongside
        // `Thermal State: critical`. Nothing below that is evidence of anything.
        min_thermal_level: Some(9),
        // Not `0`. A starved app still gets scheduled occasionally, and rounding
        // puts that at a few percent: the iPhone14,5 report that forced this
        // open showed thermal level 11 and 3% -- 2.122s of app CPU against
        // 41.210s of device CPU -- and fell outside a `0` bound, reaching the
        // manual queue as an unrecognised watchdog. What matters is the ratio,
        // and a single digit against a pegged device is the same story as zero.
        max_app_cpu_percent: Some(5),
        all_of: &[],
        none_of: &[],
        reply: THERMAL_STARVATION_REPLY,
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    const DEAD10CC_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Metadata:
  appVersion: 1.50
  deviceType: iPhone14,7
  exceptionType: 10
  osVersion: iPhone OS 26.6 (23G71)
  signal: 9
Thread 16 (attributed):
  Roam +0x54788 specialized DatabaseFileLock.withExclusiveLock<A> at /x/DatabaseFileLock.swift:37
"#;

    const GUARD_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Metadata:
  appVersion: 1.50
  deviceType: iPhone13,2
  exceptionType: 12
  signal: 0
Thread 13 (attributed):
  libswiftSystem.dylib +0x12800 FileDescriptor._close samples=1
    Roam +0x6f5a0 $defer #1  in closure #2 in scanDevicesContinually at /x samples=1
"#;

    const STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) — stack overflow
Faulting VM region: 0x16ca6fed0 is in 0x16926c000-0x16ca70000;  bytes after start: 58736336  bytes before end: 303
--->  Stack Guard                 16926c000-16ca70000    [ 56.0M] ---/rwx SM=PRV
      Stack                       16ca70000-16d26c000    [ 8176K] rw-/rwx SM=SHM
Metadata:
  appVersion: 1.51
  deviceType: iMac21,1
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.5.1 (25F80)
  signal: 11
Thread 0 (attributed — this is the thread that crashed):
  38  SwiftUI +0x1476c7c AppGraph.graphDidChange samples=1
  39  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange samples=1
  40  SwiftUI +0x1476c7c AppGraph.graphDidChange samples=1
  53  SwiftUI +0x10d76c  PlatformSceneCache.setPhase samples=1
  66  AppKit  +0x1275e8  -[NSWindow makeKeyAndOrderFront:] samples=1
  67  Roam    +0x5e2e8   NSApplication.forceFront at /x/RoamAppDelegate.swift:152 samples=1
"#;

    const WATCHDOG_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:[app<com.msdrigg.roam>:12124] Failed to terminate gracefully after 5.0s
Metadata:
  appVersion: 1.50
  deviceType: iPhone13,1
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:[app<com.msdrigg.roam>:12124] Failed to terminate gracefully after 5.0s
Thread 0 (attributed):
  Network +0x1158200 nw_browser_cancel samples=1
"#;


    /// Trimmed from the real report on thread 1540815884619227250 (roam 1.52,
    /// Mac16,12): the same graphDidChange/scenesDidChange recursion as
    /// `STACK_OVERFLOW_REPORT`, but driven by `MenuBarExtra` rather than
    /// `forceFront`. MetricKit reports the attributed thread mid-demangle
    /// because it cannot unwind an overflowed stack; the cycle is only visible
    /// in the in-process backtrace.
    const MENU_BAR_STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) — stack overflow: the faulting address is inside the Stack Guard region directly below a thread stack
Faulting VM region: 0x16d197ea0 is in 0x169994000-0x16d198000;  bytes after start: 58736288  bytes before end: 351
--->  Stack Guard                 169994000-16d198000    [ 56.0M] ---/rwx SM=PRV
Metadata:
  appVersion: 1.52
  deviceType: Mac16,12
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.6.2 (25G83)
  signal: 11
Thread 0 (attributed — this is the thread that crashed):
  0   libswiftCore.dylib +0xae994 DecodedMetadataBuilder::createGenericTypeParameterType samples=1

In-process backtrace of the faulting thread (1)
  20  SwiftUI +0x1476c7c AppGraph.graphDidChange
  21  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange
  22  SwiftUI +0x8dc94a8 $s7SwiftUI12MenuBarExtraVA2A4TextVRszrlE_10isInserted7contentACyAEq_G
  23  SwiftUI +0x1476c7c AppGraph.graphDidChange
  24  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange
"#;

    /// Trimmed from the real report on thread 1436017918377984024 (roam 1.52,
    /// iPhone12,1): `nw_browser_cancel` again, but a SIGSEGV rather than the
    /// watchdog kill `WATCHDOG_REPORT` carries.
    const LOCAL_NETWORK_RACE_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_INVALID_ADDRESS (1) / SIGSEGV (11)
Faulting VM region: 0x54 is not in any region.  Bytes before following region: 4376493996
Metadata:
  appVersion: 1.52
  deviceType: iPhone12,1
  exceptionCode: 1
  exceptionType: 1
  osVersion: iPhone OS 18.6.2 (22G100)
  signal: 11
Thread 9 (attributed — this is the thread that crashed):
  2   Network +0xadb8ec nw_browser_cancel samples=1
  3   Roam    +0x173e68 closure #1 in closure #2 in requestLocalNetworkAuthorization at /x/NetworkPermissionsCheck.swift:115 samples=1
  5   Roam    +0x1739e8 closure #2 in requestLocalNetworkAuthorization at /x/NetworkPermissionsCheck.swift:194 samples=1
"#;

    #[test]
    fn matches_the_menu_bar_extra_stack_overflow() {
        let facts = CrashFacts::from_report(MENU_BAR_STACK_OVERFLOW_REPORT);
        let matched =
            match_rule(MENU_BAR_STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "menu-bar-extra-reentrancy-stack-overflow");
        // The report is from 1.52 and the echo-drop shipped in 1.54.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_forcefront_rule_still_wins_when_both_triggers_are_present() {
        // A report carrying both belongs to the narrower forceFront rule, by
        // ordering and by this rule's `none_of`.
        let report = MENU_BAR_STACK_OVERFLOW_REPORT.replace(
            "  20  SwiftUI +0x1476c7c AppGraph.graphDidChange",
            "  20  Roam +0x5e2e8 NSApplication.forceFront at /x/RoamAppDelegate.swift:152\n  21  SwiftUI +0x1476c7c AppGraph.graphDidChange",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.rule.id),
            Some("scene-phase-reentrancy-stack-overflow")
        );
    }

    #[test]
    fn a_menu_bar_extra_crash_without_the_recursion_is_not_claimed() {
        // MenuBarExtra appears on plenty of macOS stacks. Only the cycle makes
        // this the known bug.
        let report = MENU_BAR_STACK_OVERFLOW_REPORT
            .replace("AppGraph.graphDidChange", "AppGraph.updateGraph");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn matches_the_local_network_cancel_race() {
        let facts = CrashFacts::from_report(LOCAL_NETWORK_RACE_REPORT);
        let matched = match_rule(LOCAL_NETWORK_RACE_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        // The report is from 1.52 and the claim-once wrapper shipped in 1.54.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_two_local_network_rules_do_not_steal_from_each_other() {
        // Both name `nw_browser_cancel`. The watchdog kill is EXC_CRASH with a
        // 0x8BADF00D termination code; the race is a SIGSEGV with neither.
        for (report, expected) in [
            (WATCHDOG_REPORT, "local-network-cancel-watchdog"),
            (LOCAL_NETWORK_RACE_REPORT, "local-network-cancel-race"),
        ] {
            let facts = CrashFacts::from_report(report);
            assert_eq!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some(expected)
            );
        }
    }

    #[test]
    fn a_browser_cancel_crash_outside_the_permission_check_is_not_claimed() {
        // `nw_browser_cancel` alone is any NWBrowser teardown. Without the
        // permission-check frame it stays in the manual queue.
        let report = LOCAL_NETWORK_RACE_REPORT
            .replace("requestLocalNetworkAuthorization", "scanDevicesContinually");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_new_rules_do_not_steal_the_existing_crashes() {
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
            STACK_OVERFLOW_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            let matched = match_rule(report, &facts).map(|m| m.rule.id);
            assert_ne!(matched, Some("menu-bar-extra-reentrancy-stack-overflow"));
            assert_ne!(matched, Some("local-network-cancel-race"));
            assert_ne!(matched, Some("audio-player-node-play-exception"));
        }
    }

    #[test]
    fn crash_from_1_54_onwards_is_tagged_unfixed_for_both_new_rules() {
        for (report, expected) in [
            (
                MENU_BAR_STACK_OVERFLOW_REPORT,
                "menu-bar-extra-reentrancy-stack-overflow",
            ),
            (LOCAL_NETWORK_RACE_REPORT, "local-network-cancel-race"),
        ] {
            let report = report.replace("appVersion: 1.52", "appVersion: 1.54");
            let facts = CrashFacts::from_report(&report);
            let matched = match_rule(&report, &facts).expect("still matches");
            assert_eq!(matched.rule.id, expected);
            assert_eq!(matched.status, FixStatus::Unfixed);
        }
    }

    #[test]
    fn the_1_53_reports_that_forced_these_rules_open_read_as_fixed() {
        // Both clusters had a 1.53 report in the queue; both fixes landed after
        // the v1.53 tag. If either of these flips to UNFIXED the fix regressed.
        for report in [MENU_BAR_STACK_OVERFLOW_REPORT, LOCAL_NETWORK_RACE_REPORT] {
            let report = report.replace("appVersion: 1.52", "appVersion: 1.53");
            let facts = CrashFacts::from_report(&report);
            assert_eq!(
                match_rule(&report, &facts).map(|m| m.status),
                Some(FixStatus::Fixed)
            );
        }
    }


    /// Trimmed from the real report on thread 1540766480533291048 (roam 1.51,
    /// Mac16,13): an Objective-C exception out of AVFAudio, which Swift cannot
    /// catch, so the process aborts.
    const AUDIO_PLAYER_EXCEPTION_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_CRASH (10) / code 0 / SIGABRT (6)
Metadata:
  appVersion: 1.51
  deviceType: Mac16,13
  exceptionCode: 0
  exceptionType: 10
  osVersion: macOS 26.5.2 (25F84)
  signal: 6
Thread 6 (attributed — this is the thread that crashed):
  2   libsystem_c.dylib +0x78644 abort samples=1
  5   libobjc.A.dylib   +0x24894 _objc_terminate() samples=1
  9   libobjc.A.dylib   +0x1aa84 objc_exception_throw samples=1
  10  CoreFoundation    +0xec0b0 +[NSException exceptionWithName:reason:userInfo:] samples=1
  11  AVFAudio          +0xdffa0 AVAudioPlayerNodeImpl::StartImpl(AVAudioTime*) samples=1
  13  AVFAudio          +0xdc1b4 -[AVAudioPlayerNode play] samples=1
  14  Roam              +0x2b4d94 AudioPlayer.start at /x/Loggers.swift:19 samples=1
  15  Roam              +0x1e5b00 closure #2 in closure #1 in RTPSession.streamAudio at /x/RokuSession.swift:561 samples=1
"#;

    #[test]
    fn matches_the_audio_player_node_exception() {
        let facts = CrashFacts::from_report(AUDIO_PLAYER_EXCEPTION_REPORT);
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(6));
        let matched =
            match_rule(AUDIO_PLAYER_EXCEPTION_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "audio-player-node-play-exception");
        // The report is from 1.51 and the graph rebuild shipped in 1.54.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn an_abort_without_the_audio_frames_is_not_claimed() {
        // A bare SIGABRT is not this bug. Both ends of the call must be present.
        let report =
            AUDIO_PLAYER_EXCEPTION_REPORT.replace("AudioPlayer.start", "SomeOtherThing.start");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_audio_rule_does_not_steal_the_sigkill_crashes() {
        // DEAD10CC_REPORT and THERMAL_REPORT are also EXC_CRASH. They are
        // SIGKILL, and this rule is SIGABRT -- that pair is the whole separation.
        for report in [DEAD10CC_REPORT, THERMAL_REPORT, WATCHDOG_REPORT] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("audio-player-node-play-exception")
            );
        }
    }

    #[test]
    fn extracts_facts_from_report() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        assert_eq!(facts.app_version.as_deref(), Some("1.50"));
        assert_eq!(facts.device_type.as_deref(), Some("iPhone14,7"));
        assert_eq!(facts.os_version.as_deref(), Some("iPhone OS 26.6 (23G71)"));
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(9));
        assert_eq!(facts.termination_code, None);
    }

    #[test]
    fn extracts_termination_code_case_insensitively() {
        let facts = CrashFacts::from_report(WATCHDOG_REPORT);
        assert_eq!(facts.termination_code.as_deref(), Some("0x8badf00d"));
    }

    #[test]
    fn matches_each_known_crash_to_its_own_rule() {
        for (report, expected) in [
            (DEAD10CC_REPORT, "database-lock-suspension"),
            (GUARD_REPORT, "ssdp-socket-double-close"),
            (WATCHDOG_REPORT, "local-network-cancel-watchdog"),
        ] {
            let facts = CrashFacts::from_report(report);
            let matched =
                match_rule(report, &facts).unwrap_or_else(|| panic!("no rule for {expected}"));
            assert_eq!(matched.rule.id, expected);
            // Every sample report is from 1.50; all three fixes shipped in 1.51.
            assert_eq!(matched.status, FixStatus::Fixed);
        }
    }

    #[test]
    fn matches_the_scene_phase_stack_overflow() {
        let facts = CrashFacts::from_report(STACK_OVERFLOW_REPORT);
        let matched = match_rule(STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-phase-reentrancy-stack-overflow");
        // The report is from 1.51 and the deferral shipped in 1.52.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn a_plain_forcefront_stack_overflow_is_not_claimed() {
        // Only the recursion makes this the known bug. Bringing a window forward
        // while some other code overflows the stack must stay in the queue.
        let report =
            STACK_OVERFLOW_REPORT.replace("AppGraph.graphDidChange", "AppGraph.updateGraph");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_stack_overflow_rule_does_not_steal_other_crashes() {
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("scene-phase-reentrancy-stack-overflow")
            );
        }
    }

    #[test]
    fn crash_from_the_fixing_release_is_tagged_unfixed() {
        let report = GUARD_REPORT.replace("appVersion: 1.50", "appVersion: 1.51");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("still matches the rule");
        assert_eq!(matched.rule.id, "ssdp-socket-double-close");
        assert_eq!(matched.status, FixStatus::Unfixed);
        assert!(matched.reply(&facts).contains("UNFIXED"));
    }

    #[test]
    fn crash_from_after_the_fixing_release_is_tagged_unfixed() {
        let report = GUARD_REPORT.replace("appVersion: 1.50", "appVersion: 1.52");
        let facts = CrashFacts::from_report(&report);
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.status),
            Some(FixStatus::Unfixed)
        );
    }

    #[test]
    fn crash_without_a_version_is_tagged_unknown() {
        let report = GUARD_REPORT.replace("  appVersion: 1.50\n", "");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("matching does not depend on the version");
        assert_eq!(matched.status, FixStatus::Unknown);
        assert!(matched.reply(&facts).contains("Fix status unknown"));
    }

    #[test]
    fn reply_carries_the_diagnosis_and_the_rule_footer() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        let reply = match_rule(DEAD10CC_REPORT, &facts).unwrap().reply(&facts);
        assert!(reply.contains("suspended while holding the database lock"));
        assert!(reply.contains("Fixed in 1.51"));
        assert!(reply.ends_with("_Matched automatically by rule `database-lock-suspension`._"));
    }

    #[test]
    fn versions_compare_component_wise_not_lexically() {
        // The trap: "1.5" sorts after "1.50" as a string.
        assert!(parse_version("1.5") < parse_version("1.50"));
        assert!(parse_version("1.50") < parse_version("1.51"));
        assert!(parse_version("1.51") < parse_version("1.51.1"));
        assert!(parse_version("1.51") < parse_version("2.0"));
        assert_eq!(parse_version("1.51 (204)"), parse_version("1.51"));
        assert_eq!(parse_version("1.51-beta"), parse_version("1.51"));
        assert_eq!(parse_version("unknown"), None);
        assert_eq!(parse_version(""), None);
    }

    #[test]
    fn watchdog_rule_wins_over_database_rule_for_same_exception_pair() {
        // The watchdog report is also EXC_CRASH/SIGKILL. It must not fall
        // through to the database rule, which is why ordering matters.
        let facts = CrashFacts::from_report(WATCHDOG_REPORT);
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(9));
        assert_eq!(
            match_rule(WATCHDOG_REPORT, &facts).map(|m| m.rule.id),
            Some("local-network-cancel-watchdog")
        );
    }

    #[test]
    fn unknown_crash_matches_nothing() {
        let report = r#"
Metadata:
  exceptionType: 1
  signal: 11
Thread 0 (attributed):
  Roam +0x1 someUnrelatedFunction at /x
"#;
        let facts = CrashFacts::from_report(report);
        assert!(match_rule(report, &facts).is_none());
    }

    /// Trimmed from the real report on thread 1538417638026252298 (roam 1.50,
    /// iPhone15,5): background scene-update watchdog on a device at the top of
    /// the thermal scale, with the app scheduled for 0.127s of the 40s window.
    const THERMAL_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: app<com.msdrigg.roam>:15540 exhausted real (wall clock) time allowance of 10.00 seconds
ProcessVisibility: Background
WatchdogEvent: scene-update
WatchdogCPUStatistics: (
"Elapsed total CPU time (seconds): 40.160 (user 28.900, system 11.260), 67% CPU",
"Elapsed application CPU time (seconds): 0.127, 0% CPU"
)
ThermalInfo: (
"Thermal Level:   9",
"Thermal State:   critical"
) reportType:CrashLog maxTerminationResistance:Interactive>
Metadata:
  appVersion: 1.50
  deviceType: iPhone15,5
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression
Thread 0 (attributed):
  AttributeGraph +0xc800 AG::Graph::UpdateStack::update() samples=1
"#;

    /// The iPhone14,5 report from 2026-08-20: same starvation as
    /// `THERMAL_REPORT`, but the app got a sliver of CPU rather than none, and
    /// a `max_app_cpu_percent: Some(0)` bound sent it to the manual queue.
    const THERMAL_REPORT_NONZERO_CPU: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: app<com.msdrigg.roam>:6475 exhausted real (wall clock) time allowance of 10.00 seconds
ProcessVisibility: Background
WatchdogEvent: scene-update
WatchdogCPUStatistics: (
"Elapsed total CPU time (seconds): 41.210 (user 21.740, system 19.470), 67% CPU",
"Elapsed application CPU time (seconds): 2.122, 3% CPU"
)
ThermalInfo: (
"Thermal Level:   11",
"Thermal State:   critical"
) reportType:CrashLog maxTerminationResistance:Interactive>
Metadata:
  appVersion: 1.50
  deviceType: iPhone14,5
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression
Thread 0 (attributed):
  SwiftUICore +0x29b8c BodyAccessor.setBody samples=1
"#;

    #[test]
    fn thermal_starvation_matches_when_the_app_got_a_sliver_of_cpu() {
        let facts = CrashFacts::from_report(THERMAL_REPORT_NONZERO_CPU);
        assert_eq!(facts.thermal_level, Some(11));
        assert_eq!(facts.app_cpu_percent, Some(3));

        let matched =
            match_rule(THERMAL_REPORT_NONZERO_CPU, &facts).expect("thermal rule matches at 3%");
        assert_eq!(matched.rule.id, "thermal-starvation-watchdog");
        assert_eq!(matched.status, FixStatus::NotADefect);
    }

    #[test]
    fn extracts_thermal_and_cpu_figures() {
        let facts = CrashFacts::from_report(THERMAL_REPORT);
        assert_eq!(facts.thermal_level, Some(9));
        assert_eq!(facts.app_cpu_percent, Some(0));
        // The 67% on the "Elapsed total" line is the whole device, not the app;
        // reading that one would invert the diagnosis.
        assert_ne!(facts.app_cpu_percent, Some(67));
    }

    #[test]
    fn reports_without_a_watchdog_block_carry_no_thermal_facts() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        assert_eq!(facts.thermal_level, None);
        assert_eq!(facts.app_cpu_percent, None);
    }

    #[test]
    fn thermal_starvation_is_reviewed_as_not_a_defect() {
        let facts = CrashFacts::from_report(THERMAL_REPORT);
        let matched = match_rule(THERMAL_REPORT, &facts).expect("thermal rule matches");
        assert_eq!(matched.rule.id, "thermal-starvation-watchdog");
        // Not Unfixed, so the auto-review path marks the thread reviewed rather
        // than replying and leaving it in the queue.
        assert_eq!(matched.status, FixStatus::NotADefect);
        assert_ne!(matched.status, FixStatus::Unfixed);

        let reply = matched.reply(&facts);
        assert!(reply.contains("Nothing to fix in the app"));
        // A rule with no `fixed_in` must not claim an unknown fix version.
        assert!(!reply.contains("Fix status unknown"));
        assert!(matched.review_note(&facts).contains("not an app defect"));
    }

    #[test]
    fn thermal_rule_does_not_steal_a_recognised_stack() {
        // A hot device does not stop the app from having a real bug. Any rule
        // that names an app frame has to win, which is why this one is last.
        let report = THERMAL_REPORT.replace(
            "  AttributeGraph +0xc800 AG::Graph::UpdateStack::update() samples=1",
            "  Network +0x1158200 nw_browser_cancel samples=1",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, Some(9));
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.rule.id),
            Some("local-network-cancel-watchdog")
        );
    }

    #[test]
    fn a_busy_app_on_a_hot_device_stays_in_the_manual_queue() {
        // Same thermal reading, but the app was actually running. That is a
        // watchdog kill we have not diagnosed, so it must not auto-close.
        let report = THERMAL_REPORT.replace(
            "Elapsed application CPU time (seconds): 0.127, 0% CPU",
            "Elapsed application CPU time (seconds): 31.800, 79% CPU",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.app_cpu_percent, Some(79));
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn a_starved_app_on_a_cool_device_stays_in_the_manual_queue() {
        // 0% app CPU on its own describes any blocked main thread, including
        // ones that are our fault. The thermal reading is the discriminator.
        let report = THERMAL_REPORT.replace(r#""Thermal Level:   9""#, r#""Thermal Level:   2""#);
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, Some(2));
        assert_eq!(facts.app_cpu_percent, Some(0));
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn a_watchdog_report_with_no_thermal_block_stays_in_the_manual_queue() {
        let report = THERMAL_REPORT
            .replace(r#""Thermal Level:   9""#, "")
            .replace("Elapsed application CPU time (seconds): 0.127, 0% CPU", "");
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, None);
        assert_eq!(facts.app_cpu_percent, None);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn environmental_rules_declare_no_fix_version() {
        for rule in RULES.iter().filter(|rule| rule.environmental) {
            assert!(
                rule.fixed_in.is_none(),
                "{} is environmental but names a fix version",
                rule.id
            );
        }
    }

    #[test]
    fn rule_ids_are_unique() {
        let mut ids: Vec<_> = RULES.iter().map(|r| r.id).collect();
        ids.sort_unstable();
        let count = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), count, "duplicate rule id");
    }
}
