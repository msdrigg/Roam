-- The release the reporting device was running when it uploaded the payload,
-- read off the symbolicated report's `Install:` line.
--
-- Distinct from `app_version`, which is the crash's own MetricKit `appVersion`
-- - the build that died. Payloads arrive up to a day late, so a device that
-- updated in between reports two different versions, and only the older one
-- describes the crash. Kept beside it so triage can see at a glance that a
-- matched crash is already resolved on the reporter's current build.
ALTER TABLE crash_reviews ADD COLUMN installed_version TEXT;
