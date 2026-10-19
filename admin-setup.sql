-- ============================================================
-- Admin setup for Mantra Homes customer portal
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================================

-- STEP 1: Check if you already have a portal_users record
SELECT id, email, full_name, role, company_uuids
FROM portal_users
WHERE email = 'info@mantra-homes.co.uk';

-- STEP 2a: If a row EXISTS — just upgrade it to admin
UPDATE portal_users
SET role = 'admin'
WHERE email = 'info@mantra-homes.co.uk';

-- STEP 2b: If NO row exists — create one.
-- (Only run this if the SELECT above returned nothing)
-- First, find your auth user ID:
SELECT id, email FROM auth.users WHERE email = 'info@mantra-homes.co.uk';

-- Then insert (replace <YOUR_AUTH_USER_ID> with the id from above):
INSERT INTO portal_users (auth_user_id, email, full_name, role, company_uuids)
VALUES (
  '<YOUR_AUTH_USER_ID>',   -- paste the UUID from auth.users
  'info@mantra-homes.co.uk',
  'Rishyn Patel',
  'admin',
  ARRAY[]::text[]          -- admin doesn't need company links
)
ON CONFLICT (auth_user_id) DO UPDATE SET role = 'admin';

-- ============================================================
-- After running, log in to the portal with info@mantra-homes.co.uk
-- You'll see an "Admin" section in the sidebar with:
--   • Clients  → /admin      (list all clients)
--   • Add client → /admin/invite
-- ============================================================
