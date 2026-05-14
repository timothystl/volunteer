-- Volunteer outreach messaging
-- Links signups to people records, tracks contact history, stores reusable email templates

ALTER TABLE signups ADD COLUMN person_id INTEGER DEFAULT NULL;
ALTER TABLE signups ADD COLUMN contacted_at TEXT NOT NULL DEFAULT '';
ALTER TABLE signups ADD COLUMN contact_count INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS volunteer_email_templates (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL DEFAULT '',
  ministry   TEXT NOT NULL DEFAULT '',
  subject    TEXT NOT NULL DEFAULT '',
  body       TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
