-- AU1: add email column to app_users for forgot-password flow.
ALTER TABLE app_users ADD COLUMN email TEXT NOT NULL DEFAULT '';
