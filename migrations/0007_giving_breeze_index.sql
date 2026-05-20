-- Speed up giving sync dedup, orphan cleanup, and reconcile-diagnose lookups.
CREATE INDEX IF NOT EXISTS idx_giving_breeze ON giving_entries(breeze_id);
