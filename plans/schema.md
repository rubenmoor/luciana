# schema.md

Status: partial

Postgres schema for the Luciana backend. Mirrored in Haskell as `beam` records under `Backend.Schema` (one module per table) and assembled into a single `LucianaDb` database value. Migrations are produced by `beam-migrate` from this schema.

Conventions:

- Surrogate primary keys are `BIGSERIAL` (`SERIAL8`). Cheap, monotonic, and small in indexes.
- All timestamps are `TIMESTAMPTZ` (UTC on the wire). Local-time arithmetic happens in the application using the user's stored IANA zone.
- Enum-like columns are `TEXT` with a `CHECK` constraint, mapped on the Haskell side via a `HasSqlValueSyntax` instance over a sum type. Avoids the migration headaches of native Postgres enums.
- All `created_at` columns default to `now()`.
- Deletes cascade from `users` to all per-user rows.

---

## `users`

| Column | Type | Constraints |
|---|---|---|
| `id` | `BIGSERIAL` | primary key |
| `username` | `TEXT` | not null; uniqueness enforced case-insensitively via the index below |
| `password_hash` | `TEXT` | not null |
| `locale` | `TEXT` | not null, check (`locale IN ('de','en')`) |
| `timezone` | `TEXT` | not null, IANA name (e.g. `Europe/Berlin`); refreshed from the device on every login |
| `created_at` | `TIMESTAMPTZ` | not null, default `now()` |

Indexes:
- unique expression index on `lower(username)` — preserves the user's chosen casing for display while preventing `Alice` and `alice` from coexisting.

---

## `sessions`

| Column | Type | Constraints |
|---|---|---|
| `id` | `BIGSERIAL` | primary key |
| `user_id` | `BIGINT` | not null, FK → `users(id)` ON DELETE CASCADE |
| `token_hash` | `BYTEA` | not null, unique — SHA-256 of the cookie value; raw token never stored |
| `created_at` | `TIMESTAMPTZ` | not null, default `now()` |
| `expires_at` | `TIMESTAMPTZ` | not null |

Indexes:
- unique on `token_hash` (lookup path on every authenticated request)
- btree on `expires_at` (periodic cleanup of expired rows)

---

## `period_entries`

| Column | Type | Constraints |
|---|---|---|
| `id` | `BIGSERIAL` | primary key |
| `user_id` | `BIGINT` | not null, FK → `users(id)` ON DELETE CASCADE |
| `start_date` | `DATE` | not null |
| `end_date` | `DATE` | nullable; `>= start_date` (check constraint) |
| `notes` | `TEXT` | nullable |
| `created_at` | `TIMESTAMPTZ` | not null, default `now()` |

Indexes: btree on `(user_id, start_date DESC)` — drives the home-screen "where am I in the cycle?" query and the "recent entries" list.

Constraint: `EXCLUDE USING gist` to forbid overlapping ranges per user is overkill for now; revisit if data quality becomes an issue.

---

## `push_subscriptions`

| Column | Type | Constraints |
|---|---|---|
| `id` | `BIGSERIAL` | primary key |
| `user_id` | `BIGINT` | not null, FK → `users(id)` ON DELETE CASCADE |
| `endpoint` | `TEXT` | not null, unique — the browser-issued push URL |
| `p256dh` | `TEXT` | not null — base64url-encoded ECDH public key |
| `auth` | `TEXT` | not null — base64url-encoded auth secret |
| `user_agent` | `TEXT` | nullable, captured at subscribe time for debugging |
| `created_at` | `TIMESTAMPTZ` | not null, default `now()` |
| `last_used_at` | `TIMESTAMPTZ` | nullable, updated on successful dispatch |

Indexes:
- unique on `endpoint`
- btree on `user_id`

Pruning: rows are deleted on HTTP 410 Gone from the push gateway (see `architecture.md` § Push-notification flow).

---

## `notification_prefs`

One row per user (1:1).

| Column | Type | Constraints |
|---|---|---|
| `user_id` | `BIGINT` | primary key, FK → `users(id)` ON DELETE CASCADE |
| `send_time` | `TIME` | not null — local wall-clock time, interpreted in `users.timezone` |
| `mode` | `TEXT` | not null, check (`mode IN ('Daily','YellowRed','RedOnly')`) |
| `updated_at` | `TIMESTAMPTZ` | not null, default `now()` |

The ticker can't index directly on "users due now" because dueness is computed per-row from `users.timezone` + `send_time` against UTC `now()`. At our scale (single-digit thousands of users) a full table scan once per minute is fine. If it ever becomes a bottleneck, store a precomputed `next_send_at TIMESTAMPTZ` updated on write and on dispatch, with a btree index.

---

## Haskell mapping (sketch)

```haskell
-- Backend.Schema.User
data UserT f = User
  { userId           :: C f (SqlSerial Int64)
  , userUsername     :: C f Text
  , userPasswordHash :: C f Text
  , userLocale       :: C f Locale          -- Common.I18n
  , userTimezone     :: C f TZName          -- newtype over Text
  , userCreatedAt    :: C f UTCTime
  } deriving stock (Generic)
    deriving anyclass (Beamable)
```

`LucianaDb` ties the tables together:

```haskell
data LucianaDb f = LucianaDb
  { _users              :: f (TableEntity UserT)
  , _sessions           :: f (TableEntity SessionT)
  , _periodEntries      :: f (TableEntity PeriodEntryT)
  , _pushSubscriptions  :: f (TableEntity PushSubscriptionT)
  , _notificationPrefs  :: f (TableEntity NotificationPrefT)
  } deriving stock (Generic)
    deriving anyclass (Database be)
```

Module layout:

```
backend/src/
└── Backend/
    └── Schema/
        ├── User.hs
        ├── Session.hs
        ├── PeriodEntry.hs
        ├── PushSubscription.hs
        ├── NotificationPref.hs
        └── Db.hs            -- LucianaDb + checkedLucianaDb for beam-migrate
```

---

## Migrations

`beam-migrate` is the source of truth. The first migration creates all five tables and their indexes from the schema values above. On dev, `runMigrationSilenced` applies the diff at backend startup. For production, the bootstrap step writes pending SQL to stdout and refuses to run unless the operator passes `--apply-migrations`, so deploys are auditable.

## Open

- Soft-delete on `users` vs. cascade delete: cascade for now (simpler, GDPR-friendlier — a delete is a delete). Revisit if we add features that need to retain anonymised history.
- Audit table for `period_entries` edits: out of scope for v1.
