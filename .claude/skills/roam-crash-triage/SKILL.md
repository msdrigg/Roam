---
name: roam-crash-triage
description: Triage Roam crash reports through the backend API - list unreviewed crashes, read Discord threads and messages with pagination, stream symbolicated reports and other attachments, post replies, and mark threads reviewed. Use when asked to look at crashes, check what crashes are outstanding, read a crash report or thread, reply to a crash, or work through the crash review queue. Needs only BACKEND_URL and BACKEND_API_KEY - never a Discord token.
---

# Roam crash triage

Everything here goes through the Roam backend, which proxies Discord using its
own bot credentials. **You never need a Discord token.** Two environment
variables are enough:

```bash
export BACKEND_URL=https://backend.roam.msd3.io
export BACKEND_API_KEY=...            # sent as the x-api-key header
```

A helper script wraps the endpoints below:

```bash
python3 scripts/roam_crashes.py --help
```

## How crash review works

When a crash finishes symbolicating, the backend posts `symbolicated.txt` into
the reporter's Discord thread and records the crash in `crash_reviews`. It then
runs the report against the auto-review rules:

- **A rule matches** → the backend replies in-thread with the known diagnosis
  and marks the thread reviewed as `auto:<rule id>`. Nothing left to do.
- **No rule matches** → the thread stays unreviewed. That is the queue you work.

A thread is unreviewed when it was never reviewed *or* when a newer crash
arrived after the last review, so marking a thread reviewed silences it only
until its next crash.

## Start here: what needs attention

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/crashes?unreviewed=true&limit=50"
```

Each entry carries enough to triage without downloading anything:
`thread_id`, `latest_crash_message_id`, `latest_crash_at_ms`, `app_version`,
`device_type`, `os_version`, `exception_type`, `signal`, `termination_code`,
and the review fields.

Filter and page:

| Query param | Meaning |
|---|---|
| `unreviewed=true` | only threads needing attention |
| `app_version=1.50` | exact match on the crash's `appVersion` |
| `before_ms=<ms>` | page backwards; pass the previous page's `next_before_ms` |
| `limit=<n>` | 1–200, default 50 |

`next_before_ms` in the response is the cursor for the next page, or `null` on
the last page. Loop until it is `null`.

One thread:

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" "$BACKEND_URL/v2/crashes/<thread_id>"
```

## Reading a thread

List messages, newest first (`limit` 1–100, default 50):

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages?limit=50"
```

Page further back with `before=<message_id>`, or forward with
`after=<message_id>`. IDs are strings — snowflakes exceed JavaScript's safe
integer range, so every id in these APIs is a string on the wire.

One message:

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages/<message_id>"
```

All threads in the support forum (`archived_pages` walks 100 archived threads
per page, 0 = active only, max 20):

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/discord/threads?archived_pages=3"
```

## Downloading documents

Attachments stream straight through the backend from Discord's CDN — nothing is
buffered server-side, so large diagnostics dumps are fine. Take the
`attachments[].id` from a message and:

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages/<message_id>/attachments/<attachment_id>" \
  -o symbolicated.txt
```

Write it to a file and read that, rather than piping a whole report into
context. The interesting parts of a symbolicated report are:

- `Termination reason:` and `Diagnosis:` — present when the payload carried one;
  these name the OS policy that killed the process
- the `Metadata:` block — `exceptionType`, `signal`, `appVersion`, `deviceType`
- the thread marked `(attributed)` — the only stack that caused the crash

Read the attributed thread. Other threads are usually idle and will mislead you.

## Replying and marking reviewed

Post a reply (mentions are always suppressed):

```bash
curl -s -X POST -H "x-api-key: $BACKEND_API_KEY" -H "Content-Type: application/json" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages" \
  -d '{"content": "...", "reply_to_message_id": "<crash_message_id>"}'
```

Then mark the thread reviewed. Every field is optional:

```bash
curl -s -X POST -H "x-api-key: $BACKEND_API_KEY" -H "Content-Type: application/json" \
  "$BACKEND_URL/v2/crashes/<thread_id>/review" \
  -d '{"reviewed_by": "scott", "reviewed_message_id": "<reply_id>", "note": "..."}'
```

Reopen one you want to revisit:

```bash
curl -s -X DELETE -H "x-api-key: $BACKEND_API_KEY" \
  "$BACKEND_URL/v2/crashes/<thread_id>/review"
```

## Auto-review rules

```bash
curl -s -H "x-api-key: $BACKEND_API_KEY" "$BACKEND_URL/v2/crashes/rules"
```

Rules live in `backend/src/crash_rules.rs` as a compiled-in list, matched in
order with first-match-wins. Each has an `id`, optional `exception_type` /
`signal` / `termination_code`, `all_of` / `none_of` substrings matched against
the report text, and the `reply` markdown that gets posted.

**When you diagnose a crash that recurs, add a rule** rather than replying by
hand a second time. Put narrower rules first — several distinct bugs share
`EXC_CRASH (10)` / `SIGKILL (9)`, so a rule keyed only on that pair will
swallow others. Add a test in the same file covering the new report shape and
asserting it does not steal matches from existing rules.

## Working the queue

1. `GET /v2/crashes?unreviewed=true` — see what is outstanding.
2. For each, download the `symbolicated.txt` attachment and read the attributed
   thread.
3. Recognisable and already fixed → reply, mark reviewed, and consider adding a
   rule so it self-serves next time.
4. Novel → diagnose it, fix it in the app, then reply, mark reviewed, and add a
   rule.

Do not mark a thread reviewed without actually replying to it; the review flag
is a record that someone answered, not that someone looked.
