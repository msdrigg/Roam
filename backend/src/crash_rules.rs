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

impl CrashFacts {
    pub fn from_report(report: &str) -> Self {
        Self {
            app_version: metadata_value(report, "appVersion"),
            device_type: metadata_value(report, "deviceType"),
            os_version: metadata_value(report, "osVersion"),
            exception_type: metadata_value(report, "exceptionType")
                .and_then(|v| v.parse().ok()),
            signal: metadata_value(report, "signal").and_then(|v| v.parse().ok()),
            termination_code: termination_code(report),
        }
    }
}

/// A single auto-review rule. All specified conditions must hold.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashRule {
    pub id: &'static str,
    pub title: &'static str,
    /// Mach exception type, e.g. 10 for `EXC_CRASH`, 12 for `EXC_GUARD`.
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    /// Lowercase hex termination code, e.g. `0x8badf00d`.
    pub termination_code: Option<&'static str>,
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
        if !self.all_of.iter().all(|needle| report.contains(needle)) {
            return false;
        }
        if self.none_of.iter().any(|needle| report.contains(needle)) {
            return false;
        }
        true
    }
}

/// Returns the first rule matching the report, if any.
pub fn match_rule(report: &str, facts: &CrashFacts) -> Option<&'static CrashRule> {
    RULES.iter().find(|rule| rule.matches(report, facts))
}

const DEAD10CC_REPLY: &str = ":ninja: **Auto-review: `0xdead10cc` — suspended while holding the database lock**

`EXC_CRASH (10)` / `SIGKILL (9)` with the attributed thread in the middle of a database write. This is not a fault in the app's own code — iOS killed the process deliberately.

Persistent writes hold an exclusive `flock` on a lock file in the shared app-group container, on top of the SQLite/WAL locks on `Roam.sqlite` beside it. A suspended process still holding those can block the widget extension indefinitely, so the system terminates it.

**Known cause, fix shipped:**
- a background-task assertion is held across every persistent write, so the process stays alive long enough to commit and release the lock
- the file lock covers the transaction only — it used to be held across a full snapshot reload that scans every table
- automatic device discovery stops when the app is backgrounded, removing the main source of writes still in flight at suspension time

_Matched automatically by rule `database-lock-suspension`._";

const EXC_GUARD_REPLY: &str = ":ninja: **Auto-review: `EXC_GUARD` — the SSDP socket was closed twice**

`EXC_GUARD (12)`, attributed to `close()` inside the `defer` in `scanDevicesContinually`.

That function closed its UDP socket in two places: the `onCancel` handler of `withTaskCancellationHandler` (which is what interrupts the blocking `receiveFrom`), and the body's own `defer` as it unwinds. On cancellation both run, so `close(2)` fires twice on the same descriptor. By the second call the kernel has usually reused that number, and when the new owner is a *guarded* descriptor — GRDB's SQLite handles and Network.framework both guard theirs — the process is killed on the spot.

`try? socket.close()` cannot defend against this: `EXC_GUARD` is a Mach exception, not an `errno`.

**Known cause, fix shipped:** both paths now go through a close-once wrapper, so the descriptor reaches `close(2)` exactly once regardless of which path wins the race.

_Matched automatically by rule `ssdp-socket-double-close`._";

const WATCHDOG_REPLY: &str = ":ninja: **Auto-review: `0x8BADF00D` watchdog — main thread blocked cancelling the Bonjour browser**

The termination reason pins this down: the process failed to terminate within its 5 second budget.

The attributed thread is the **main thread**, parked in `nw_browser_cancel`, reached from `requestLocalNetworkAuthorization`'s `onCancel` handler.

`onCancel` runs synchronously on whichever thread cancels the task, and SwiftUI cancels `.task` work on the main thread while it applies a scene-phase change. `NWBrowser.cancel()` and `NWListener.cancel()` block on an internal Network.framework lock, so when the network queue is busy the main thread stalls past the termination budget and the watchdog kills the app.

**Known cause, fix shipped:** listener/browser teardown is dispatched onto the queue those objects already run on, so the cancelling thread is never blocked.

_Matched automatically by rule `local-network-cancel-watchdog`._";

/// Ordered: the first match wins, so put narrower rules first.
pub static RULES: &[CrashRule] = &[
    CrashRule {
        id: "local-network-cancel-watchdog",
        title: "0x8BADF00D watchdog cancelling NWBrowser on the main thread",
        exception_type: None,
        signal: None,
        termination_code: Some("0x8badf00d"),
        all_of: &["nw_browser_cancel"],
        none_of: &[],
        reply: WATCHDOG_REPLY,
    },
    CrashRule {
        id: "ssdp-socket-double-close",
        title: "EXC_GUARD from double-closing the SSDP socket",
        exception_type: Some(12),
        signal: None,
        termination_code: None,
        all_of: &["scanDevicesContinually", "FileDescriptor._close"],
        none_of: &[],
        reply: EXC_GUARD_REPLY,
    },
    CrashRule {
        id: "database-lock-suspension",
        title: "0xdead10cc suspension while holding the database file lock",
        exception_type: Some(10),
        signal: Some(9),
        termination_code: None,
        all_of: &["DatabaseFileLock.withExclusiveLock"],
        none_of: &[],
        reply: DEAD10CC_REPLY,
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
            let rule = match_rule(report, &facts).unwrap_or_else(|| panic!("no rule for {expected}"));
            assert_eq!(rule.id, expected);
        }
    }

    #[test]
    fn watchdog_rule_wins_over_database_rule_for_same_exception_pair() {
        // The watchdog report is also EXC_CRASH/SIGKILL. It must not fall
        // through to the database rule, which is why ordering matters.
        let facts = CrashFacts::from_report(WATCHDOG_REPORT);
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(9));
        assert_eq!(
            match_rule(WATCHDOG_REPORT, &facts).map(|r| r.id),
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

    #[test]
    fn rule_ids_are_unique() {
        let mut ids: Vec<_> = RULES.iter().map(|r| r.id).collect();
        ids.sort_unstable();
        let count = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), count, "duplicate rule id");
    }
}
