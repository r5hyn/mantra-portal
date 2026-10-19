-- ============================================================
-- Mantra Homes Customer Portal — Supabase Schema
-- Run this in: Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- ── 1. portal_users ──────────────────────────────────────────
-- Links a Supabase auth user to one or more ServiceM8 companies.
create table if not exists portal_users (
  id              uuid primary key default gen_random_uuid(),
  auth_user_id    uuid references auth.users(id) on delete cascade,
  email           text not null,
  full_name       text,
  company_uuids   text[] not null default '{}',
  role            text not null default 'customer',  -- 'customer' | 'admin'
  invited_by      text,
  created_at      timestamptz default now()
);

alter table portal_users enable row level security;

-- Customers can only read their own row
create policy "portal_users: own row" on portal_users
  for select using (auth.uid() = auth_user_id);

-- Service role (server-side API) bypasses RLS automatically

-- ── 2. invites ───────────────────────────────────────────────
-- Tracks pending invitations before the customer accepts.
create table if not exists invites (
  id              uuid primary key default gen_random_uuid(),
  email           text not null,
  company_uuids   text[] not null default '{}',
  invited_by      text,
  accepted_at     timestamptz,
  expires_at      timestamptz not null default (now() + interval '7 days'),
  created_at      timestamptz default now()
);

alter table invites enable row level security;
-- Only accessible via service role (server-side)

-- ── 3. job_messages ──────────────────────────────────────────
-- Per-job chat between customer and Mantra staff.
create table if not exists job_messages (
  id                  uuid primary key default gen_random_uuid(),
  job_uuid            text not null,
  sender_type         text not null check (sender_type in ('customer', 'staff')),
  sender_name         text not null,
  sender_id           uuid references portal_users(id) on delete set null,
  body                text,
  attachments         jsonb not null default '[]',
  read_by_staff       boolean not null default false,
  read_by_customer    boolean not null default false,
  created_at          timestamptz default now()
);

alter table job_messages enable row level security;

-- Customers can read messages on jobs that belong to their companies.
-- We store company_uuid on the message for efficient RLS.
-- (The API layer verifies job ownership before inserting.)
create policy "job_messages: customer read own jobs" on job_messages
  for select using (
    sender_id in (
      select id from portal_users where auth_user_id = auth.uid()
    )
    or
    exists (
      select 1 from portal_users pu
      where pu.auth_user_id = auth.uid()
        and pu.id = sender_id
    )
  );

-- Customers can insert their own messages (sender_id must match their portal_users.id)
create policy "job_messages: customer insert own" on job_messages
  for insert with check (
    sender_type = 'customer'
    and sender_id in (
      select id from portal_users where auth_user_id = auth.uid()
    )
  );

-- ── 4. notifications ─────────────────────────────────────────
create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references portal_users(id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text,
  job_uuid    text,
  is_read     boolean not null default false,
  created_at  timestamptz default now()
);

alter table notifications enable row level security;

create policy "notifications: own" on notifications
  for all using (
    user_id in (select id from portal_users where auth_user_id = auth.uid())
  );

-- ── 5. announcements ─────────────────────────────────────────
create table if not exists announcements (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  body          text not null,
  is_important  boolean not null default false,
  target        text not null default 'all' check (target in ('all', 'specific')),
  target_uuids  text[] not null default '{}',
  published_at  timestamptz,
  created_by    text,
  created_at    timestamptz default now()
);

alter table announcements enable row level security;

-- Published announcements visible to all customers,
-- or to those whose company UUID is in target_uuids
create policy "announcements: visible to customer" on announcements
  for select using (
    published_at is not null
    and published_at <= now()
    and (
      target = 'all'
      or exists (
        select 1 from portal_users pu
        where pu.auth_user_id = auth.uid()
          and pu.company_uuids && target_uuids
      )
    )
  );

-- ── 6. Realtime ──────────────────────────────────────────────
-- Enable realtime for live chat and notifications
alter publication supabase_realtime add table job_messages;
alter publication supabase_realtime add table notifications;

-- ── 7. Indexes ───────────────────────────────────────────────
create index if not exists idx_job_messages_job_uuid on job_messages(job_uuid);
create index if not exists idx_notifications_user_id on notifications(user_id, is_read);
create index if not exists idx_portal_users_auth on portal_users(auth_user_id);
create index if not exists idx_announcements_published on announcements(published_at desc);

-- ── Client-added properties (addresses) ─────────────────────────────────────
create table if not exists client_properties (
  id           uuid primary key default gen_random_uuid(),
  company_uuid text not null,
  address      text not null,
  label        text default '',
  created_by   uuid,
  created_at   timestamptz default now()
);
create index if not exists client_properties_company_idx on client_properties (company_uuid);
alter table client_properties enable row level security;

-- ── Notes / photos approved for clients to see ──────────────────────────────
create table if not exists job_shared_items (
  id         uuid primary key default gen_random_uuid(),
  job_uuid   text not null,
  item_uuid  text not null unique,
  item_type  text not null check (item_type in ('note','attachment')),
  shared_by  uuid,
  created_at timestamptz default now()
);
create index if not exists job_shared_items_job_idx on job_shared_items (job_uuid);
alter table job_shared_items enable row level security;

-- ── Xero connection (single row) + client ↔ Xero contact links ──────────────
create table if not exists xero_connection (
  id            int primary key default 1,
  tenant_id     text,
  tenant_name   text,
  access_token  text,
  refresh_token text,
  expires_at    timestamptz,
  connected_at  timestamptz,
  updated_at    timestamptz default now()
);
alter table xero_connection enable row level security;

create table if not exists xero_contact_links (
  company_uuid      text primary key,
  xero_contact_id   text,
  xero_contact_name text default '',
  updated_at        timestamptz default now()
);
alter table xero_contact_links enable row level security;
