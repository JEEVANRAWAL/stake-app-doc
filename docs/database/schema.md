# Phase 2 — Comprehensive Database Design (PostgreSQL 15+)
### Commitment-Based Digital Discipline App ("Bhaakal")

Design principles:
- **Money:** `NUMERIC(14,4)` everywhere; explicit `currency` (ISO-4217); no floats.
- **Time:** all timestamps `TIMESTAMPTZ` (UTC). Device-local values stored separately, never trusted for enforcement.
- **Ledger:** append-only, double-entry, immutable rows, isolated in its own `ledger` schema.
- **High-write tables** (`usage_events`, `notifications`) range-partitioned by time.
- **State machines** via `ENUM`s + `CHECK`/transition guards.
- Surrogate `UUID` PKs (`gen_random_uuid()`).

## Extensions, schemas, enums

```sql
-- ============ EXTENSIONS & SCHEMAS ============
CREATE EXTENSION IF NOT EXISTS pgcrypto;     -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;       -- case-insensitive email
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- exclusion constraints on ranges

CREATE SCHEMA IF NOT EXISTS core;     -- users, devices, rules
CREATE SCHEMA IF NOT EXISTS billing;  -- payments, wallets
CREATE SCHEMA IF NOT EXISTS ledger;   -- isolated double-entry ledger
CREATE SCHEMA IF NOT EXISTS usage;    -- high-frequency telemetry
CREATE SCHEMA IF NOT EXISTS engage;   -- streaks, notifications, analytics

-- ============ ENUM TYPES ============
CREATE TYPE core.os_platform           AS ENUM ('android','ios');
CREATE TYPE core.account_status        AS ENUM ('pending_verification','active','suspended','deactivated','deleted');
CREATE TYPE core.auth_provider         AS ENUM ('password','google','apple','phone_otp');
CREATE TYPE core.day_of_week           AS ENUM ('mon','tue','wed','thu','fri','sat','sun');
CREATE TYPE core.schedule_type         AS ENUM ('daily','weekdays','weekends','custom');
CREATE TYPE core.rule_status           AS ENUM ('active','paused','removed');
CREATE TYPE core.cooldown_state        AS ENUM ('none','limit_reached','in_paid_unlock','locked_window');

CREATE TYPE billing.payment_provider   AS ENUM ('stripe','esewa','khalti','fonepay','apple_iap','google_iap','wallet_internal','connectips','manual_bank');
CREATE TYPE billing.withdrawal_status   AS ENUM ('requested','under_review','approved','processing','paid','rejected','failed','cancelled');
CREATE TYPE billing.payment_purpose    AS ENUM ('wallet_topup','unlock_fee','commitment_break_fee','deposit_stake','withdrawal');
CREATE TYPE billing.payment_status     AS ENUM ('initiated','pending','authorized','succeeded','failed','cancelled','refunded','partially_refunded','disputed');
CREATE TYPE billing.wallet_status      AS ENUM ('active','frozen','closed');
CREATE TYPE billing.deposit_status     AS ENUM ('active','completed_returned','forfeited','partially_forfeited','cancelled');

CREATE TYPE ledger.account_type        AS ENUM ('user_available','user_locked','user_payout_pending','system_forfeit_revenue','system_charity','system_gateway_clearing','system_fees');
CREATE TYPE ledger.entry_direction     AS ENUM ('debit','credit');

CREATE TYPE usage.violation_type       AS ENUM ('schedule_block','time_limit_reached','permission_revoked','force_stop','app_uninstalled','clock_tamper','clone_detected');
CREATE TYPE usage.enforcement_action   AS ENUM ('blocked','allowed_paid_unlock','penalty_applied','warning','grace_period');
CREATE TYPE usage.unlock_status        AS ENUM ('requested','payment_pending','granted','expired','denied');

CREATE TYPE engage.notification_type   AS ENUM ('limit_warning','limit_reached','commitment_break','payment_receipt','streak_milestone','protection_down','generic');
CREATE TYPE engage.notification_status AS ENUM ('scheduled','queued','sent','delivered','failed','cancelled');
```

## Core: users, auth, devices

```sql
-- ============ USERS ============
CREATE TABLE core.users (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                   CITEXT UNIQUE,
    phone_e164              VARCHAR(20) UNIQUE,
    full_name               VARCHAR(160),
    avatar_url              TEXT,
    account_status          core.account_status NOT NULL DEFAULT 'pending_verification',
    email_verified_at       TIMESTAMPTZ,
    phone_verified_at       TIMESTAMPTZ,
    default_currency        CHAR(3) NOT NULL DEFAULT 'NPR',
    locale                  VARCHAR(12) NOT NULL DEFAULT 'en-NP',
    timezone                VARCHAR(64) NOT NULL DEFAULT 'Asia/Kathmandu',
    day_boundary_minutes    INTEGER NOT NULL DEFAULT 0
                            CHECK (day_boundary_minutes BETWEEN 0 AND 1439),
    marketing_opt_in        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    CONSTRAINT chk_contact_present CHECK (email IS NOT NULL OR phone_e164 IS NOT NULL)
);

-- ============ AUTH IDENTITIES ============
CREATE TABLE core.auth_identities (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    provider                core.auth_provider NOT NULL,
    provider_subject        VARCHAR(255),
    password_hash           TEXT,
    last_login_at           TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_subject)
);

-- ============ SESSIONS / REFRESH TOKENS ============
CREATE TABLE core.sessions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    device_id               UUID,
    refresh_token_hash      TEXT NOT NULL,
    issued_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ NOT NULL,
    revoked_at              TIMESTAMPTZ,
    ip_address              INET,
    user_agent              TEXT
);

-- ============ DEVICES ============
CREATE TABLE core.devices (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    os_platform             core.os_platform NOT NULL,
    os_version              VARCHAR(32),
    app_version             VARCHAR(32),
    device_model            VARCHAR(120),
    hardware_id_hash        VARCHAR(128),
    push_token              TEXT,
    push_provider           VARCHAR(16),
    accessibility_granted   BOOLEAN NOT NULL DEFAULT FALSE,
    usage_access_granted    BOOLEAN NOT NULL DEFAULT FALSE,
    family_controls_granted BOOLEAN NOT NULL DEFAULT FALSE,
    overlay_granted         BOOLEAN NOT NULL DEFAULT FALSE,
    battery_optimized       BOOLEAN,
    integrity_verified      BOOLEAN NOT NULL DEFAULT FALSE,
    last_heartbeat_at       TIMESTAMPTZ,
    last_seen_clock_skew_ms BIGINT,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, hardware_id_hash)
);

ALTER TABLE core.sessions
    ADD CONSTRAINT fk_sessions_device
    FOREIGN KEY (device_id) REFERENCES core.devices(id) ON DELETE SET NULL;

CREATE INDEX idx_devices_user            ON core.devices(user_id);
CREATE INDEX idx_devices_heartbeat       ON core.devices(last_heartbeat_at) WHERE is_active;
CREATE INDEX idx_sessions_user_active    ON core.sessions(user_id) WHERE revoked_at IS NULL;
```

## Core: restricted apps, schedules, screen-time rules

```sql
-- ============ APP CATALOG ============
CREATE TABLE core.app_catalog (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    android_package_name    VARCHAR(255),
    ios_bundle_id           VARCHAR(255),
    display_name            VARCHAR(160) NOT NULL,
    category                VARCHAR(64),
    icon_url                TEXT,
    icon_checksum           VARCHAR(128),
    is_high_risk            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_app_identifier CHECK (android_package_name IS NOT NULL OR ios_bundle_id IS NOT NULL),
    UNIQUE (android_package_name),
    UNIQUE (ios_bundle_id)
);

-- ============ USER ↔ RESTRICTED APP ============
CREATE TABLE core.user_restricted_apps (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    app_catalog_id          UUID REFERENCES core.app_catalog(id),
    ios_application_token   TEXT,
    label_override          VARCHAR(160),
    status                  core.rule_status NOT NULL DEFAULT 'active',
    added_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    removed_at              TIMESTAMPTZ,
    removal_payment_id      UUID,
    UNIQUE (user_id, app_catalog_id),
    CONSTRAINT chk_app_ref CHECK (app_catalog_id IS NOT NULL OR ios_application_token IS NOT NULL)
);
CREATE INDEX idx_ura_user_active ON core.user_restricted_apps(user_id) WHERE status = 'active';

-- ============ RESTRICTION SCHEDULES ============
CREATE TABLE core.restriction_schedules (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    user_restricted_app_id  UUID NOT NULL REFERENCES core.user_restricted_apps(id) ON DELETE CASCADE,
    schedule_type           core.schedule_type NOT NULL,
    start_minute            INTEGER NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
    end_minute              INTEGER NOT NULL CHECK (end_minute BETWEEN 1 AND 1440),
    crosses_midnight        BOOLEAN NOT NULL DEFAULT FALSE,
    status                  core.rule_status NOT NULL DEFAULT 'active',
    is_currently_locked     BOOLEAN NOT NULL DEFAULT FALSE,
    locked_until            TIMESTAMPTZ,
    effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_window CHECK (crosses_midnight OR start_minute < end_minute)
);

CREATE TABLE core.restriction_schedule_days (
    schedule_id             UUID NOT NULL REFERENCES core.restriction_schedules(id) ON DELETE CASCADE,
    day                     core.day_of_week NOT NULL,
    PRIMARY KEY (schedule_id, day)
);
CREATE INDEX idx_sched_user_active ON core.restriction_schedules(user_id) WHERE status = 'active';

-- ============ SCREEN-TIME RULES ============
CREATE TABLE core.screen_time_rules (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    user_restricted_app_id  UUID NOT NULL REFERENCES core.user_restricted_apps(id) ON DELETE CASCADE,
    daily_limit_seconds     INTEGER NOT NULL CHECK (daily_limit_seconds >= 0),
    min_committed_seconds   INTEGER NOT NULL DEFAULT 0,
    status                  core.rule_status NOT NULL DEFAULT 'active',
    cooldown_state          core.cooldown_state NOT NULL DEFAULT 'none',
    current_day_key         DATE NOT NULL DEFAULT CURRENT_DATE,
    current_usage_seconds   INTEGER NOT NULL DEFAULT 0,
    limit_reached_at        TIMESTAMPTZ,
    last_increase_payment_id UUID,
    pending_limit_seconds   INTEGER CHECK (pending_limit_seconds >= 0),  -- staged increase (next-day, anti-binge)
    pending_effective_day_key DATE,                                      -- when the staged increase applies
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_restricted_app_id),
    CONSTRAINT chk_usage_nonneg CHECK (current_usage_seconds >= 0)
);
CREATE INDEX idx_str_user_active ON core.screen_time_rules(user_id) WHERE status = 'active';
```

## Billing & isolated double-entry ledger

```sql
-- ============ WALLETS ============
CREATE TABLE billing.wallets (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE RESTRICT,
    currency                CHAR(3) NOT NULL,
    status                  billing.wallet_status NOT NULL DEFAULT 'active',
    available_balance       NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (available_balance >= 0),
    locked_balance          NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (locked_balance >= 0),
    version                 BIGINT NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, currency)
);

-- ============ COMMITMENT DEPOSITS ============
CREATE TABLE billing.commitment_deposits (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE RESTRICT,
    wallet_id               UUID NOT NULL REFERENCES billing.wallets(id),
    staked_amount           NUMERIC(14,4) NOT NULL CHECK (staked_amount > 0),
    forfeited_amount        NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (forfeited_amount >= 0),
    returned_amount         NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (returned_amount >= 0),
    currency                CHAR(3) NOT NULL,
    status                  billing.deposit_status NOT NULL DEFAULT 'active',
    commitment_start        TIMESTAMPTZ NOT NULL DEFAULT now(),
    commitment_end          TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_deposit_math CHECK (forfeited_amount + returned_amount <= staked_amount)
);
CREATE INDEX idx_deposits_user_active ON billing.commitment_deposits(user_id) WHERE status = 'active';

-- ============ PAYMENTS ============
CREATE TABLE billing.payments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE RESTRICT,
    wallet_id               UUID REFERENCES billing.wallets(id),
    provider                billing.payment_provider NOT NULL,
    purpose                 billing.payment_purpose NOT NULL,
    status                  billing.payment_status NOT NULL DEFAULT 'initiated',
    amount                  NUMERIC(14,4) NOT NULL CHECK (amount > 0),
    currency                CHAR(3) NOT NULL,
    fee_amount              NUMERIC(14,4) NOT NULL DEFAULT 0,
    net_amount              NUMERIC(14,4),
    provider_intent_id      VARCHAR(191),
    provider_reference      VARCHAR(191),
    provider_raw_response   JSONB,
    idempotency_key         VARCHAR(191) NOT NULL,
    failure_code            VARCHAR(64),
    failure_message         TEXT,
    initiated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    authorized_at           TIMESTAMPTZ,
    succeeded_at            TIMESTAMPTZ,
    failed_at               TIMESTAMPTZ,
    settled_at              TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_intent_id),
    UNIQUE (idempotency_key)
);
CREATE INDEX idx_payments_user        ON billing.payments(user_id, created_at DESC);
CREATE INDEX idx_payments_status      ON billing.payments(status) WHERE status IN ('initiated','pending','authorized');
CREATE INDEX idx_payments_provider_ref ON billing.payments(provider, provider_reference);

-- ============ PAYMENT WEBHOOK EVENTS (idempotent inbox / audit) ============
CREATE TABLE billing.payment_webhook_events (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider                billing.payment_provider NOT NULL,
    provider_event_id       VARCHAR(191) NOT NULL,
    payment_id              UUID REFERENCES billing.payments(id),
    event_type              VARCHAR(128) NOT NULL,
    signature_verified      BOOLEAN NOT NULL DEFAULT FALSE,
    payload                 JSONB NOT NULL,
    processed_at            TIMESTAMPTZ,
    received_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_event_id)
);

-- ============ WITHDRAWALS (payout / money-out) ============
CREATE TABLE billing.withdrawals (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE RESTRICT,
    wallet_id               UUID NOT NULL REFERENCES billing.wallets(id),
    status                  billing.withdrawal_status NOT NULL DEFAULT 'requested',
    amount                  NUMERIC(14,4) NOT NULL CHECK (amount > 0),  -- debited from wallet
    fee_amount              NUMERIC(14,4) NOT NULL DEFAULT 0,           -- borne by user (gross-down)
    payout_amount           NUMERIC(14,4),                              -- amount - fee, sent to user
    currency                CHAR(3) NOT NULL,
    provider                billing.payment_provider NOT NULL,          -- 'manual_bank' | 'connectips'
    dest_bank_code          VARCHAR(32),
    dest_account_no         VARCHAR(64),
    dest_account_name       VARCHAR(128),
    kyc_tier_at_request     SMALLINT NOT NULL,
    reviewed_by             UUID REFERENCES core.users(id),
    review_note             TEXT,
    disburse_reference      VARCHAR(191),                               -- idempotent payout ref (no double-pay)
    batch_id                UUID,
    failure_code            VARCHAR(64),
    requested_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at             TIMESTAMPTZ,
    paid_at                 TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, disburse_reference)                              -- guards against duplicate disbursement
);
CREATE INDEX idx_withdrawals_user   ON billing.withdrawals(user_id, requested_at DESC);
CREATE INDEX idx_withdrawals_queue  ON billing.withdrawals(status) WHERE status IN ('requested','under_review','approved','processing');

-- ============ ISOLATED DOUBLE-ENTRY LEDGER ============
CREATE TABLE ledger.accounts (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id           UUID REFERENCES core.users(id),
    account_type            ledger.account_type NOT NULL,
    currency                CHAR(3) NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (owner_user_id, account_type, currency)
);

CREATE TABLE ledger.journals (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reference_type          VARCHAR(48) NOT NULL,
    reference_id            UUID NOT NULL,
    description             TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ledger.entries (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    journal_id              UUID NOT NULL REFERENCES ledger.journals(id) ON DELETE RESTRICT,
    account_id              UUID NOT NULL REFERENCES ledger.accounts(id) ON DELETE RESTRICT,
    direction               ledger.entry_direction NOT NULL,
    amount                  NUMERIC(14,4) NOT NULL CHECK (amount > 0),
    currency                CHAR(3) NOT NULL,
    balance_after           NUMERIC(14,4),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_entries_account ON ledger.entries(account_id, id);
CREATE INDEX idx_ledger_entries_journal ON ledger.entries(journal_id);

-- Append-only guard
CREATE OR REPLACE FUNCTION ledger.forbid_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'ledger.entries is append-only; % not allowed', TG_OP;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trg_ledger_immutable
    BEFORE UPDATE OR DELETE ON ledger.entries
    FOR EACH ROW EXECUTE FUNCTION ledger.forbid_mutation();
```

## Usage telemetry, violations, unlocks (high-write, partitioned)

```sql
-- ============ RAW USAGE EVENTS (partitioned monthly) ============
CREATE TABLE usage.usage_events (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id                 UUID NOT NULL,
    device_id               UUID NOT NULL,
    user_restricted_app_id  UUID,
    event_type              VARCHAR(32) NOT NULL,
    duration_seconds        INTEGER NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
    device_local_ts         TIMESTAMPTZ,
    server_ts               TIMESTAMPTZ NOT NULL DEFAULT now(),
    monotonic_elapsed_ms    BIGINT,
    sync_batch_id           UUID,
    PRIMARY KEY (id, server_ts)
) PARTITION BY RANGE (server_ts);

CREATE TABLE usage.usage_events_2026_06 PARTITION OF usage.usage_events
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE usage.usage_events_2026_07 PARTITION OF usage.usage_events
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');

CREATE INDEX idx_usage_events_user_ts ON usage.usage_events (user_id, server_ts DESC);
CREATE INDEX idx_usage_events_app     ON usage.usage_events (user_restricted_app_id, server_ts DESC);

-- ============ VIOLATIONS ============
CREATE TABLE usage.violations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    device_id               UUID REFERENCES core.devices(id),
    user_restricted_app_id  UUID REFERENCES core.user_restricted_apps(id),
    violation_type          usage.violation_type NOT NULL,
    enforcement_action      usage.enforcement_action NOT NULL,
    fee_applied             NUMERIC(14,4) NOT NULL DEFAULT 0,
    currency                CHAR(3) NOT NULL DEFAULT 'NPR',
    related_payment_id      UUID REFERENCES billing.payments(id),
    related_journal_id      UUID REFERENCES ledger.journals(id),
    detected_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    device_local_ts         TIMESTAMPTZ,
    notes                   JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_violations_user_time ON usage.violations(user_id, detected_at DESC);
CREATE INDEX idx_violations_type      ON usage.violations(violation_type, detected_at DESC);

-- ============ UNLOCK REQUESTS ============
CREATE TABLE usage.unlock_requests (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    device_id               UUID REFERENCES core.devices(id),
    user_restricted_app_id  UUID NOT NULL REFERENCES core.user_restricted_apps(id),
    status                  usage.unlock_status NOT NULL DEFAULT 'requested',
    duration_seconds        INTEGER NOT NULL CHECK (duration_seconds > 0),
    fee_amount              NUMERIC(14,4) NOT NULL CHECK (fee_amount >= 0),
    currency                CHAR(3) NOT NULL DEFAULT 'NPR',
    payment_id              UUID REFERENCES billing.payments(id),
    journal_id              UUID REFERENCES ledger.journals(id),
    authorization_token     VARCHAR(255),
    granted_at              TIMESTAMPTZ,
    expires_at              TIMESTAMPTZ,
    requested_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_unlock_active ON usage.unlock_requests(user_id, expires_at) WHERE status = 'granted';
```

## Analytics, streaks, notifications

```sql
-- ============ DAILY ANALYTICS SNAPSHOTS ============
CREATE TABLE engage.daily_snapshots (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    snapshot_date           DATE NOT NULL,
    total_screen_seconds    INTEGER NOT NULL DEFAULT 0,
    restricted_app_seconds  INTEGER NOT NULL DEFAULT 0,
    blocks_enforced         INTEGER NOT NULL DEFAULT 0,
    paid_unlocks            INTEGER NOT NULL DEFAULT 0,
    commitment_breaks       INTEGER NOT NULL DEFAULT 0,
    total_fees_paid         NUMERIC(14,4) NOT NULL DEFAULT 0,
    focus_score             NUMERIC(5,2),
    computed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, snapshot_date)
);
CREATE INDEX idx_snapshots_user_date ON engage.daily_snapshots(user_id, snapshot_date DESC);

-- ============ PER-APP DAILY DURATION ============
CREATE TABLE engage.daily_app_usage (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    user_restricted_app_id  UUID NOT NULL REFERENCES core.user_restricted_apps(id) ON DELETE CASCADE,
    snapshot_date           DATE NOT NULL,
    used_seconds            INTEGER NOT NULL DEFAULT 0,
    limit_seconds           INTEGER,
    over_limit              BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (user_restricted_app_id, snapshot_date)
);

-- ============ STREAKS & GAMIFICATION ============
-- Folded lazily on read (GET /v1/gamification), user-local day boundary via
-- core.user_today. Semantics (locked 2026-07-04): a complete day with >=1
-- armed restricted app and no penalty EXTENDS the streak; a penalty
-- (usage.violations enforcement_action='penalty_applied') RESETS it; a day
-- with nothing armed PAUSES it (no advance, no reset — idle days can't farm
-- streaks). Paid unlocks / paid commitment-breaks are sanctioned spends and
-- never break the streak. Today never accrues (a day counts once complete),
-- but a penalty today zeroes the display immediately.
-- productivity_score / total_money_saved / level are dormant for MVP.
CREATE TABLE engage.gamification_state (
    user_id                 UUID PRIMARY KEY REFERENCES core.users(id) ON DELETE CASCADE,
    current_streak_days     INTEGER NOT NULL DEFAULT 0,
    longest_streak_days     INTEGER NOT NULL DEFAULT 0,
    last_active_date        DATE,
    last_clean_date         DATE,
    evaluated_through       DATE,           -- fold cursor: last evaluated local day
    productivity_score      NUMERIC(6,2) NOT NULL DEFAULT 0,
    total_money_saved       NUMERIC(14,4) NOT NULL DEFAULT 0,
    level                   INTEGER NOT NULL DEFAULT 1,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ NOTIFICATIONS (partitioned by send time) ============
CREATE TABLE engage.notifications (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id                 UUID NOT NULL,
    device_id               UUID,
    type                    engage.notification_type NOT NULL,
    status                  engage.notification_status NOT NULL DEFAULT 'scheduled',
    title                   VARCHAR(180),
    body                    TEXT,
    payload                 JSONB,
    scheduled_for           TIMESTAMPTZ NOT NULL,
    sent_at                 TIMESTAMPTZ,
    delivered_at            TIMESTAMPTZ,
    failure_reason          TEXT,
    provider_message_id     VARCHAR(191),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, scheduled_for)
) PARTITION BY RANGE (scheduled_for);

CREATE TABLE engage.notifications_2026_06 PARTITION OF engage.notifications
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

CREATE INDEX idx_notif_due  ON engage.notifications (scheduled_for) WHERE status = 'scheduled';
CREATE INDEX idx_notif_user ON engage.notifications (user_id, created_at DESC);
```

## ER overview, indexing strategy & ledger isolation notes

**Relationships:** `users 1—N devices/auth_identities/sessions`; `users 1—N user_restricted_apps N—1
app_catalog`; `user_restricted_apps 1—N restriction_schedules 1—N restriction_schedule_days`;
`user_restricted_apps 1—1 screen_time_rules`; `users 1—1 wallets[currency]`; `wallets 1—N
commitment_deposits/payments`; `ledger.journals 1—N ledger.entries N—1 ledger.accounts` (each journal
nets to zero); `users 1—N violations/unlock_requests`; `users 1—N daily_snapshots 1—N daily_app_usage`;
`users 1—1 gamification_state`; `users 1—N notifications`.

**Indexing strategy for high-frequency writes:**
1. **Partition the firehose tables** (`usage_events`, `notifications`) by `RANGE(server_ts/scheduled_for)` monthly. Writes hit only the current hot partition; old partitions detach/archive cheaply.
2. **Keep hot tables lean on indexes** — `usage_events` carries only two secondary indexes.
3. **Don't aggregate on the write path** — devices batch-sync raw events; async workers roll them into counters/snapshots. Live enforcement reads the cached `current_usage_seconds`.
4. **Partial indexes for "active" working sets** (`WHERE status='active'`, `WHERE revoked_at IS NULL`, `WHERE status='granted'`).
5. **Heartbeat/anti-cheat scans** ride `idx_devices_heartbeat` (partial on `is_active`).
6. Use **monotonic `elapsed_realtime`** for elapsed-time accounting; compare on `server_ts`, never on `device_local_ts`.

**Financial ledger isolation:**
- Lives in its own `ledger` schema with **separate DB roles**: app role gets `INSERT`-only; `UPDATE`/`DELETE` revoked + blocked by `forbid_mutation` trigger → provably append-only.
- **Double-entry, journal-atomic:** every money movement writes one `journal` + ≥2 balanced `entries` in a single DB transaction; `sum(debits)=sum(credits)`.
- Cached `wallets.available_balance/locked_balance` are **derived**, reconciled nightly against `SUM(ledger.entries)`. Ledger is the source of truth.
- **Balance mutations use pessimistic locking** (`SELECT … FOR UPDATE`) + `version` optimistic checks → no double-spend.
- **Idempotency everywhere:** `payments.idempotency_key` (unique) and `payment_webhook_events (provider, provider_event_id)` (unique) make retries/replays safe.
- **Deposit = wallet lock:** staking moves `user_available → user_locked`; forfeiture moves `user_locked → system_forfeit_revenue/charity`; completion moves `user_locked → user_available`. Money never leaves the ledger's closed system.
