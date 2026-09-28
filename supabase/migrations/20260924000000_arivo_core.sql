-- Arivo core schema. PostGIS for places, pgvector for embeddings, RLS everywhere.
-- Data domains are separated: profile · trip · booking (restricted) · payment references · AI · security/audit.

create extension if not exists postgis;
create extension if not exists vector;
create extension if not exists pg_trgm;
create extension if not exists pgcrypto;

create schema if not exists arivo;
create schema if not exists restricted; -- booking passengers, PII token maps: service role only, no client access

-- ------------------------------------------------------------------------------------------------ identity & profile
create table arivo.users (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Traveller',
  home_city text,
  home_currency char(3) not null default 'MYR',
  created_at timestamptz not null default now()
);

create table arivo.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references arivo.users (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web')),
  integrity_verdict text,             -- Play Integrity / App Attest result: a risk signal, not proof
  last_seen_at timestamptz not null default now()
);

create table arivo.traveler_profiles (
  user_id uuid primary key references arivo.users (id) on delete cascade,
  dna jsonb not null,                  -- TravelerDNA (always editable by the traveller)
  embedding vector(64),                -- TravelerEmbedding for hybrid ranking
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------------------------------------------ places
create table arivo.destinations (
  key text primary key,                -- tokyo, kyoto, kuala-lumpur
  name text not null,
  country char(2) not null,
  tz text not null,
  currency char(3) not null,
  bbox geography(polygon, 4326) not null
);

create table arivo.places (
  id text primary key,                 -- osm:node:123 / wd:Q123
  destination text not null references arivo.destinations (key),
  name text not null,
  name_local text,
  category text not null,
  geom geography(point, 4326) not null,
  indoor boolean not null default false,
  dna jsonb not null default '{}',
  duration_min int[] check (duration_min is null or array_length(duration_min, 1) = 3),
  tags jsonb not null default '{}',
  iconic real not null default 0,
  notability int not null default 0,
  quality smallint not null default 0,
  summary text,
  wikipedia_en text,
  photo jsonb,
  embedding vector(64),                -- PlaceEmbedding
  updated_at timestamptz not null default now()
);
create index places_geom_gix on arivo.places using gist (geom);
create index places_dest_cat_idx on arivo.places (destination, category);
create index places_name_trgm on arivo.places using gin (name gin_trgm_ops);
create index places_embedding_idx on arivo.places using hnsw (embedding vector_cosine_ops);

create table arivo.place_sources (
  place_id text not null references arivo.places (id) on delete cascade,
  name text not null,                  -- OpenStreetMap, Wikidata, Wikimedia Commons, supplier …
  url text,
  license text,
  retrieved_at timestamptz not null default now(),
  primary key (place_id, name)
);

-- ------------------------------------------------------------------------------------------------ trips (Living Trip)
create table arivo.trips (
  id text primary key,
  owner_id uuid not null references arivo.users (id) on delete cascade,
  title text not null,
  start_date date not null,
  timezone text not null,
  currency char(3) not null,
  home_currency char(3) not null,
  mode text not null default 'planner' check (mode in ('planner', 'live')),
  doc jsonb not null,                  -- the full Trip document (days, items, Plan B) — versioned below
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table arivo.trip_members (
  trip_id text not null references arivo.trips (id) on delete cascade,
  user_id uuid not null references arivo.users (id) on delete cascade,
  role text not null check (role in ('owner', 'editor', 'member', 'viewer')),
  color_index smallint not null default 0,
  share_location boolean not null default false,  -- exact location is never broadcast unless the member opts in
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create table arivo.crew_preferences (
  trip_id text not null references arivo.trips (id) on delete cascade,
  user_id uuid not null references arivo.users (id) on delete cascade,
  dna jsonb not null,
  must_do text[] not null default '{}',
  dietary text[] not null default '{}',
  private boolean not null default false,
  primary key (trip_id, user_id)
);

-- normalised projections of trip.doc for queries/analytics (rebuilt from doc on every version)
create table arivo.itinerary_days (
  trip_id text not null references arivo.trips (id) on delete cascade,
  day_index smallint not null,
  date date not null,
  title text,
  weather jsonb,
  primary key (trip_id, day_index)
);

create table arivo.itinerary_items (
  id text primary key,
  trip_id text not null references arivo.trips (id) on delete cascade,
  day_index smallint not null,
  place_id text,
  kind text not null,
  starts_at timestamp not null,        -- local wall time in trip timezone
  duration_min int not null check (duration_min > 0),
  status text not null,
  locked boolean not null default false,
  booking_id text,
  cost_minor bigint,
  cost_currency char(3)
);
create index itinerary_items_trip_idx on arivo.itinerary_items (trip_id, day_index, starts_at);

create table arivo.trip_changes (
  id text primary key,
  trip_id text not null references arivo.trips (id) on delete cascade,
  day_index smallint not null,
  trigger text not null,
  status text not null check (status in ('proposed', 'applied', 'rejected')),
  base_version int not null,
  diff jsonb not null,                 -- kept / moved / removed / added + deltas + explanation
  actor uuid,
  created_at timestamptz not null default now()
);

create table arivo.saved_places (
  user_id uuid not null references arivo.users (id) on delete cascade,
  place_id text not null references arivo.places (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

create table arivo.budgets (
  trip_id text primary key references arivo.trips (id) on delete cascade,
  total_minor bigint not null,
  currency char(3) not null,
  style text not null default 'balanced',
  lines jsonb not null
);

create table arivo.expenses (
  id text primary key,
  trip_id text not null references arivo.trips (id) on delete cascade,
  created_by uuid not null references arivo.users (id),
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  category text not null,
  merchant text,
  note text,
  source text not null check (source in ('manual', 'receipt_lens', 'booking')),
  created_at timestamptz not null default now()
);

create table arivo.votes (
  trip_id text not null references arivo.trips (id) on delete cascade,
  suggestion_id text not null,
  user_id uuid not null references arivo.users (id) on delete cascade,
  value smallint not null check (value in (-1, 0, 1)),
  primary key (trip_id, suggestion_id, user_id)
);

create table arivo.recommendations (
  id bigserial primary key,
  trip_id text references arivo.trips (id) on delete cascade,
  place_id text not null references arivo.places (id),
  score real not null,
  components jsonb not null,
  lane text,
  created_at timestamptz not null default now()
);

create table arivo.recommendation_evidence (
  recommendation_id bigint not null references arivo.recommendations (id) on delete cascade,
  text text not null,
  provenance text not null check (provenance in ('live', 'est', 'you')),
  source text,
  url text,
  updated_at timestamptz
);

-- ------------------------------------------------------------------------------------------------ Arivo Pulse (partition-ready)
create table arivo.trend_signals (
  id bigserial,
  place_id text not null,
  source text not null,
  fetched_at timestamptz not null,
  payload jsonb not null,
  primary key (id, fetched_at)
) partition by range (fetched_at);
create table arivo.trend_signals_default partition of arivo.trend_signals default;

create table arivo.trend_snapshots (
  place_id text not null references arivo.places (id) on delete cascade,
  computed_at timestamptz not null,
  score real not null check (score between 0 and 100),
  components jsonb not null,
  spam_penalty real not null,
  label text,
  evidence jsonb not null,
  primary key (place_id, computed_at)
);

-- ------------------------------------------------------------------------------------------------ bookings (restricted domain)
create table arivo.offers_cache (      -- short-lived supplier quotes; purged after expiry (retention: 1 day)
  user_id uuid not null,
  offer_id text not null,
  offer jsonb not null,                -- normalised TravelOffer only, never raw supplier payload
  cached_at timestamptz not null default now(),
  primary key (user_id, offer_id)
);

create table arivo.booking_transactions (
  id text primary key,
  user_id uuid not null references arivo.users (id),
  trip_id text not null references arivo.trips (id),
  idempotency_key text not null,
  state text not null,
  offer jsonb not null,
  provider text not null,
  total_minor bigint not null,
  currency char(3) not null,
  payment_ref text,                    -- PSP id only. No PAN, no CVV, ever.
  supplier_ref text,
  booking_reference text,
  needs_reconciliation boolean not null default false,
  sandbox boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, idempotency_key)    -- the database, not the app, guarantees one booking per key
);
create index booking_txn_reconcile_idx on arivo.booking_transactions (state) where needs_reconciliation;

create table arivo.bookings (
  id text primary key references arivo.booking_transactions (id),
  trip_id text not null references arivo.trips (id),
  kind text not null check (kind in ('flight', 'stay', 'bus', 'rail', 'activity')),
  summary jsonb not null,              -- what the traveller sees offline (route, times, ref)
  status text not null
);

create table restricted.booking_passengers (
  transaction_id text not null references arivo.booking_transactions (id) on delete cascade,
  idx smallint not null,
  encrypted_payload bytea not null,    -- name/dob/contact, encrypted with a KMS-held key
  primary key (transaction_id, idx)
);

create table arivo.booking_events (
  id bigserial,
  transaction_id text not null,
  at timestamptz not null default now(),
  from_state text,
  to_state text not null,
  note text,
  actor text,
  primary key (id, at)
) partition by range (at);
create table arivo.booking_events_default partition of arivo.booking_events default;

create table arivo.payments (
  id text primary key,                 -- PSP PaymentIntent id
  transaction_id text not null references arivo.booking_transactions (id),
  status text not null,
  amount_minor bigint not null,
  currency char(3) not null,
  risk_level text
);

create table arivo.refunds (
  id text primary key,
  payment_id text not null references arivo.payments (id),
  amount_minor bigint not null,
  status text not null,
  created_at timestamptz not null default now()
);

create table arivo.supplier_events (   -- inbound webhooks, deduplicated by provider event id
  provider text not null,
  event_id text not null,
  received_at timestamptz not null default now(),
  signature_ok boolean not null,
  payload jsonb not null,
  processed_at timestamptz,
  primary key (provider, event_id)
);

create table arivo.outbox (
  id text primary key,
  type text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  dispatched_at timestamptz
);
create index outbox_pending_idx on arivo.outbox (created_at) where dispatched_at is null;

-- ------------------------------------------------------------------------------------------------ AI, security, audit
create table arivo.agent_actions (
  id bigserial primary key,
  trip_id text references arivo.trips (id) on delete cascade,
  user_id uuid not null,
  tool text not null,
  scope text not null,
  proposal jsonb,
  confirmed boolean not null default false,
  created_at timestamptz not null default now()
);

create table restricted.pii_token_maps (
  id bigserial primary key,
  user_id uuid not null,
  sealed bytea not null,               -- Fernet-encrypted token map; never sent to model providers
  expires_at timestamptz not null
);

create table arivo.security_events (
  id bigserial,
  at timestamptz not null default now(),
  kind text not null,                  -- login_failed, credential_stuffing, risk_hold, webhook_bad_signature, enumeration …
  user_id uuid,
  ip inet,
  detail jsonb not null default '{}',
  primary key (id, at)
) partition by range (at);
create table arivo.security_events_default partition of arivo.security_events default;

create table arivo.audit_events (
  id bigserial,
  at timestamptz not null default now(),
  actor text not null,
  action text not null,
  target text not null,
  result text not null,
  request_id text,
  meta jsonb not null default '{}',    -- never card data or secrets
  primary key (id, at)
) partition by range (at);
create table arivo.audit_events_default partition of arivo.audit_events default;

create table arivo.offline_packs (
  id text primary key,
  trip_id text not null references arivo.trips (id) on delete cascade,
  user_id uuid not null references arivo.users (id) on delete cascade,
  version int not null,
  manifest jsonb not null,
  created_at timestamptz not null default now()
);

create table arivo.notifications (
  id bigserial,
  user_id uuid not null,
  at timestamptz not null default now(),
  kind text not null,
  body jsonb not null,
  read_at timestamptz,
  primary key (id, at)
) partition by range (at);
create table arivo.notifications_default partition of arivo.notifications default;

create table arivo.user_feedback (
  id bigserial primary key,
  user_id uuid not null references arivo.users (id) on delete cascade,
  trip_id text references arivo.trips (id) on delete cascade,
  place_id text,
  kind text not null,                  -- why_removed, not_for_me, relevance_rating …
  value text,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------------------------------------------ Row-Level Security
-- Membership is resolved in the database. The API also checks it (defence in depth), but the database never
-- relies on the client hiding UI.
create or replace function arivo.trip_role(t text) returns text
language sql stable security definer set search_path = arivo as $$
  select case when exists (select 1 from arivo.trips where id = t and owner_id = auth.uid()) then 'owner'
              else (select role from arivo.trip_members where trip_id = t and user_id = auth.uid()) end
$$;

create or replace function arivo.can(t text, minimum text) returns boolean
language sql stable as $$
  select coalesce(array_position(array['viewer','member','editor','owner'], arivo.trip_role(t))
                  >= array_position(array['viewer','member','editor','owner'], minimum), false)
$$;

alter table arivo.users enable row level security;
alter table arivo.devices enable row level security;
alter table arivo.traveler_profiles enable row level security;
alter table arivo.trips enable row level security;
alter table arivo.trip_members enable row level security;
alter table arivo.crew_preferences enable row level security;
alter table arivo.itinerary_days enable row level security;
alter table arivo.itinerary_items enable row level security;
alter table arivo.trip_changes enable row level security;
alter table arivo.saved_places enable row level security;
alter table arivo.budgets enable row level security;
alter table arivo.expenses enable row level security;
alter table arivo.votes enable row level security;
alter table arivo.booking_transactions enable row level security;
alter table arivo.bookings enable row level security;
alter table arivo.offline_packs enable row level security;
alter table arivo.places enable row level security;
alter table arivo.destinations enable row level security;
alter table arivo.trend_snapshots enable row level security;
alter table arivo.recommendations enable row level security;
alter table arivo.recommendation_evidence enable row level security;
alter table arivo.notifications enable row level security;
alter table arivo.user_feedback enable row level security;
alter table arivo.offers_cache enable row level security;
alter table arivo.payments enable row level security;
alter table arivo.refunds enable row level security;
alter table arivo.booking_events enable row level security;
alter table arivo.supplier_events enable row level security;
alter table arivo.outbox enable row level security;
alter table arivo.agent_actions enable row level security;
alter table arivo.security_events enable row level security;
alter table arivo.audit_events enable row level security;
alter table arivo.trend_signals enable row level security;

-- self-owned rows
create policy self_users on arivo.users for all using (id = auth.uid()) with check (id = auth.uid());
create policy self_devices on arivo.devices for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy self_profile on arivo.traveler_profiles for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy self_saved on arivo.saved_places for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy self_packs on arivo.offline_packs for all using (user_id = auth.uid() and arivo.can(trip_id, 'viewer')) with check (user_id = auth.uid());
create policy self_notifications on arivo.notifications for select using (user_id = auth.uid());
create policy self_feedback on arivo.user_feedback for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- trip-scoped rows (viewer can read, editor can write; bookings only by their owner)
create policy trips_read on arivo.trips for select using (arivo.can(id, 'viewer'));
create policy trips_insert on arivo.trips for insert with check (owner_id = auth.uid());
create policy trips_update on arivo.trips for update using (arivo.can(id, 'editor')) with check (arivo.can(id, 'editor'));
create policy trips_delete on arivo.trips for delete using (owner_id = auth.uid());
create policy members_read on arivo.trip_members for select using (arivo.can(trip_id, 'viewer'));
create policy members_manage on arivo.trip_members for all using (arivo.can(trip_id, 'owner')) with check (arivo.can(trip_id, 'owner'));
create policy prefs_read on arivo.crew_preferences for select using (arivo.can(trip_id, 'viewer') and (not private or user_id = auth.uid()));
create policy prefs_write on arivo.crew_preferences for all using (user_id = auth.uid() and arivo.can(trip_id, 'member')) with check (user_id = auth.uid());
create policy days_read on arivo.itinerary_days for select using (arivo.can(trip_id, 'viewer'));
create policy items_read on arivo.itinerary_items for select using (arivo.can(trip_id, 'viewer'));
create policy changes_read on arivo.trip_changes for select using (arivo.can(trip_id, 'viewer'));
create policy budgets_read on arivo.budgets for select using (arivo.can(trip_id, 'viewer'));
create policy expenses_read on arivo.expenses for select using (arivo.can(trip_id, 'viewer'));
create policy expenses_write on arivo.expenses for insert with check (created_by = auth.uid() and arivo.can(trip_id, 'member'));
create policy votes_rw on arivo.votes for all using (arivo.can(trip_id, 'viewer')) with check (user_id = auth.uid() and arivo.can(trip_id, 'member'));
create policy txn_owner on arivo.booking_transactions for select using (user_id = auth.uid());
create policy bookings_trip on arivo.bookings for select using (arivo.can(trip_id, 'viewer'));
create policy recs_read on arivo.recommendations for select using (trip_id is null or arivo.can(trip_id, 'viewer'));
create policy recev_read on arivo.recommendation_evidence for select using (true);
create policy offers_owner on arivo.offers_cache for select using (user_id = auth.uid());

-- public reference data (read-only for signed-in users)
create policy places_read on arivo.places for select to authenticated using (true);
create policy destinations_read on arivo.destinations for select to authenticated using (true);
create policy trends_read on arivo.trend_snapshots for select to authenticated using (true);
-- payments, refunds, booking_events, supplier_events, outbox, agent_actions, security/audit events, trend_signals:
-- RLS enabled with NO client policies → only the service role (backend) can touch them.

revoke all on schema restricted from anon, authenticated;

-- ------------------------------------------------------------------------------------------------ retention (pg_cron in production)
-- delete from arivo.offers_cache where cached_at < now() - interval '1 day';
-- delete from arivo.trend_signals where fetched_at < now() - interval '120 days';
-- delete from restricted.pii_token_maps where expires_at < now();

-- ------------------------------------------------------------------------------------------------ grants
-- Table privileges are granted to `authenticated`; RLS policies above decide which ROWS each user can touch.
grant usage on schema arivo to authenticated;
grant select on all tables in schema arivo to authenticated;
grant insert, update, delete on arivo.users, arivo.devices, arivo.traveler_profiles, arivo.saved_places, arivo.trips,
  arivo.trip_members, arivo.crew_preferences, arivo.expenses, arivo.votes, arivo.offline_packs, arivo.user_feedback to authenticated;
revoke all on arivo.payments, arivo.refunds, arivo.booking_events, arivo.supplier_events, arivo.outbox, arivo.agent_actions,
  arivo.security_events, arivo.audit_events, arivo.trend_signals from authenticated, anon;
