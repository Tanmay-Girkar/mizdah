# Password Change + Forgot Password — Backend Spec

Two related but separate flows that together cover **every** way a
user can update their password in the Mizdah app:

| Flow | Triggered from | User must prove identity via |
|---|---|---|
| **Change password** (logged in) | Settings → Edit profile → Change password | Their **current password** (typed in the sheet) |
| **Forgot password / reset** (not logged in) | Login screen → "Forgot password?" link | A **single-use token** delivered by email |

Both are intentionally split: the logged-in user changing their
password is a different threat model than someone who can't log in
at all. Don't try to merge them into one endpoint.

Total backend work: **~3 hours**

- §3 Extend `/api/auth/update` to require `current_password`: **30 min**
- §4 New `POST /api/auth/forgot-password`: **45 min**
- §5 New `POST /api/auth/reset-password`: **45 min**
- §2 + §6 Token table + cleanup job: **30 min**
- §7 Rate limits + abuse caps: **15 min**
- §8 Test cases: **30 min**

---

## 0. Conventions

Same as the rest of the docs in this folder:

- Gateway: `https://<dev-host>:3001` (dev),
  `https://mizdah-backend.ogoul.cloud` (prod).
- Auth: `Authorization: Bearer <JWT>` required where stated.
- Bodies: `application/json`.
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.
- Timestamps: ISO-8601 UTC.

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| Require `current_password` on every password-change call | `POST /api/auth/update` | NEW behaviour (existing endpoint extended) |
| New endpoint: request password-reset email | `POST /api/auth/forgot-password` | NEW |
| New endpoint: consume reset token to set new password | `POST /api/auth/reset-password` | NEW |
| `password_reset_tokens` table | DB | NEW |
| Optional: `session_revoked_at` column on users to log out other sessions | DB | NEW (recommended) |

---

## 2. Data model — new table + optional column

### 2.1 `password_reset_tokens` (NEW)

```sql
CREATE TABLE password_reset_tokens (
  -- Random opaque token sent in the email link. NEVER stored in
  -- plaintext — we keep only the SHA-256 hash so a DB leak doesn't
  -- give the attacker live reset links. The raw token leaves the
  -- server exactly once (inside the email body).
  token_hash       CHAR(64) PRIMARY KEY,
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Expiration. Spec calls for 15 min — keep this short enough that
  -- a leaked email a day later is useless, long enough that the user
  -- can switch apps to find the email.
  expires_at       TIMESTAMPTZ NOT NULL,
  -- Single-use: flip this true when the token is consumed via
  -- POST /api/auth/reset-password. Don't delete on consumption —
  -- keeping the row lets us return `TOKEN_ALREADY_USED` instead of
  -- the generic `TOKEN_INVALID`, which is a cleaner UX.
  consumed_at      TIMESTAMPTZ,
  -- Audit trail: tells the on-call engineer "who requested this".
  requested_ip     INET,
  requested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cleanup queries: expired or consumed rows are deleted by a
-- nightly cron. The "active token per user" lookup hits this index.
CREATE INDEX password_reset_tokens_user_active_idx
  ON password_reset_tokens (user_id, expires_at)
  WHERE consumed_at IS NULL;
```

Nightly cleanup (cron or a one-line job):

```sql
DELETE FROM password_reset_tokens
WHERE expires_at < NOW() - INTERVAL '7 days';
```

### 2.2 `users.session_revoked_at` (OPTIONAL — recommended)

Lets a successful password change OR reset invalidate every JWT
issued before that timestamp, which is the standard "log out other
sessions" behaviour:

```sql
ALTER TABLE users
  ADD COLUMN session_revoked_at TIMESTAMPTZ;
```

Then in your JWT verification middleware, reject any token whose
`iat` (issued-at) is **earlier** than `users.session_revoked_at`.
The user's own active token issued AFTER the password change/reset
stays valid because its `iat` is newer.

If you don't want this column, the alternative is rotating the JWT
signing key globally — much heavier-handed. Recommend the column.

---

## 3. Endpoint — extend `POST /api/auth/update` with current-password verification

### 3.1 Today's behaviour (probably)

The endpoint already accepts an optional `password` field and
writes it. **That's the security hole**: anyone with a valid JWT
(stolen unlocked phone, leaked token in a log, malicious browser
extension etc.) can rewrite the user's password without proving
they know it.

### 3.2 New behaviour

When the request body contains a `password` field, ALSO require a
`current_password` field and verify it. Other fields (`name`,
`avatar_url`, `phone`) keep their existing behaviour — no
`current_password` needed for those.

```jsonc
POST /api/auth/update
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "password":         "newSecret123",  // optional; triggers §3.3
  "current_password": "oldSecret",     // REQUIRED when `password` is present

  // Existing fields stay as they are:
  "name":             "...",
  "avatar_url":       "...",
  "phone":            "...",
  "phone_country":    "..."
}
```

### 3.3 Validation (when `password` is present)

In order. Stop at the first failure with the matching 4xx code:

| # | Rule | Failure code |
|---|---|---|
| 1 | `current_password` field is present, non-empty | `MISSING_CURRENT_PASSWORD` (400) |
| 2 | `current_password` verifies against `users.password_hash` | `INVALID_CURRENT_PASSWORD` (403) |
| 3 | `password` (new) is ≥ 8 characters | `WEAK_PASSWORD` (400) |
| 4 | `password` (new) ≠ `current_password` | `SAME_AS_CURRENT_PASSWORD` (400) |
| 5 | Per-user rate limit on failed current-password checks (5/h) | `RATE_LIMITED` (429) |

Hash comparison **must be constant-time** (bcrypt `compare()` or
argon2 `verify()` — never `==`) to avoid timing-attack leakage.

### 3.4 Success response

Same shape as today — the full updated user object. **Bump
`session_revoked_at` to NOW()** so other devices get force-logged-
out on next request:

```sql
UPDATE users
SET password_hash       = $1,
    password_changed_at = NOW(),
    session_revoked_at  = NOW()
WHERE id = $userId;
```

Issue a fresh JWT in the response (or via `Set-Cookie`) so the
calling client survives the global revocation:

```jsonc
HTTP/1.1 200 OK
{
  "user":  { ... },
  "token": "<fresh JWT, iat = NOW()>"
}
```

The Flutter client already extracts the new token from
`set-cookie`; if you put it in the body too, even better.

### 3.5 Error response examples

```jsonc
HTTP/1.1 403 Forbidden
{
  "error": "Current password is incorrect.",
  "code":  "INVALID_CURRENT_PASSWORD"
}
```

```jsonc
HTTP/1.1 400 Bad Request
{
  "error": "New password must be different from current password.",
  "code":  "SAME_AS_CURRENT_PASSWORD"
}
```

```jsonc
HTTP/1.1 429 Too Many Requests
Retry-After: 600
{
  "error": "Too many incorrect current-password attempts. Try again later.",
  "code":  "RATE_LIMITED"
}
```

---

## 4. Endpoint — NEW `POST /api/auth/forgot-password`

Public endpoint (no JWT). User types their email on the Forgot-
password screen; backend looks up the account, generates a single-
use reset token, stores its hash in `password_reset_tokens`, emails
the user a link containing the **raw** token.

### 4.1 Request

```jsonc
POST /api/auth/forgot-password
Content-Type: application/json
(no auth)

{
  "email": "alice@example.com"
}
```

### 4.2 Behaviour

1. **Always return 200** with the same body — DO NOT reveal whether
   the email exists. (Email-enumeration via this endpoint is the #1
   abuse vector for forgot-password flows.) See §7 for why and the
   alternative if you prefer "transparent" responses.
2. If the email **exists**:
   - Generate a 32-byte cryptographically-random token. Hex- or
     base64url-encode (URL-safe — it goes in a query string). 64
     hex chars = 256 bits of entropy.
   - SHA-256 the token; store the hash in
     `password_reset_tokens.token_hash`.
   - Set `expires_at = NOW() + 15 minutes`.
   - **Invalidate any previously-issued unconsumed tokens for this
     user** (`UPDATE … SET consumed_at = NOW() WHERE user_id = …
     AND consumed_at IS NULL`). Only the latest link works — limits
     blast radius if the user forwards an old email by mistake.
   - Send the email (§10 template):
     ```
     Subject: Reset your Mizdah password

     We received a request to reset the password for this Mizdah
     account. If this wasn't you, ignore this email.

     Reset link (expires in 15 minutes):
     https://mizdah.app/reset-password?token=<RAW_TOKEN>

     The link can be used once and expires automatically.
     ```
3. If the email **doesn't exist**:
   - Skip all of the above silently (no DB write, no email).
   - Sleep for a small random delay (50-300 ms) so timing doesn't
     leak existence either.

### 4.3 Response — always the same

```jsonc
HTTP/1.1 200 OK
{
  "ok": true,
  "message": "If an account exists for that email, we sent a reset link."
}
```

The Flutter client shows that exact message to the user. The user
doesn't know if the email worked; if they typo'd the email, they
get the same "if exists" copy and figure it out themselves.

### 4.4 Errors

Only structural errors return non-200:

| HTTP | `code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | `email` missing or not a valid format |
| 429 | `RATE_LIMITED` | Per-IP or per-email cap (§7) hit |

---

## 5. Endpoint — NEW `POST /api/auth/reset-password`

Public endpoint. User taps the email link, lands on the in-app
reset screen (or web fallback), types a new password, submits.

### 5.1 Request

```jsonc
POST /api/auth/reset-password
Content-Type: application/json
(no auth)

{
  "token":    "<RAW_TOKEN from email link>",
  "password": "newSecret123"
}
```

### 5.2 Validation

| # | Rule | Failure code |
|---|---|---|
| 1 | `token` non-empty | `BAD_REQUEST` (400) |
| 2 | `password` ≥ 8 chars | `WEAK_PASSWORD` (400) |
| 3 | SHA-256(`token`) matches a row in `password_reset_tokens` | `TOKEN_INVALID` (400) |
| 4 | That row has `consumed_at IS NULL` | `TOKEN_ALREADY_USED` (400) |
| 5 | That row has `expires_at > NOW()` | `TOKEN_EXPIRED` (400) |
| 6 | Per-IP rate limit on attempts (10/h) | `RATE_LIMITED` (429) |

### 5.3 Success

Atomically:

```sql
BEGIN;
  -- Verify the token row exists, isn't consumed, isn't expired —
  -- if any check fails, ROLLBACK and return the matching error
  -- code from §5.2.

  UPDATE password_reset_tokens
  SET    consumed_at = NOW()
  WHERE  token_hash = $1;

  UPDATE users
  SET    password_hash       = $2,
         password_changed_at = NOW(),
         session_revoked_at  = NOW()   -- log out all other sessions
  WHERE  id = (SELECT user_id FROM password_reset_tokens
               WHERE token_hash = $1);
COMMIT;
```

Issue a fresh JWT in the response so the user lands logged in
without an extra round-trip:

```jsonc
HTTP/1.1 200 OK
{
  "user":  { ... full user object ... },
  "token": "<fresh JWT>"
}
```

The Flutter client routes the user straight to Home after this
response, matching the rest of the auth flow.

### 5.4 Errors

| HTTP | `code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | structural |
| 400 | `WEAK_PASSWORD` | new password < 8 chars |
| 400 | `TOKEN_INVALID` | no matching token_hash |
| 400 | `TOKEN_ALREADY_USED` | already consumed |
| 400 | `TOKEN_EXPIRED` | past `expires_at` |
| 429 | `RATE_LIMITED` | per-IP cap |

Note: **distinguishing `TOKEN_INVALID` from `TOKEN_EXPIRED`** is
fine here because the attacker already needs to have a candidate
token to make the request, which is hard. The differentiation
helps the legitimate user (who got the email two days late) see
a useful error instead of "invalid".

---

## 6. Reset-token security details

- **Source of randomness**: `crypto.randomBytes(32)` (Node),
  `secrets.token_urlsafe(32)` (Python), `RandomNumberGenerator`
  (Java/Kotlin). NEVER `Math.random()`.
- **Storage**: only the SHA-256 hash. Plaintext token leaves the
  server exactly once, inside the email body.
- **Single-use**: enforced via `consumed_at`. A second attempt to
  use the same token returns `TOKEN_ALREADY_USED`.
- **Expiration**: 15 minutes. Long enough for the user to find the
  email, short enough that a leaked email log from yesterday is
  worthless.
- **One active token per user**: requesting a new reset
  invalidates all previous unconsumed ones (§4.2).
- **Token in URL**: query parameter is fine. The link is sent over
  TLS-encrypted email; even if the user pastes the URL into a
  search bar (rare), the token's single-use + 15-min expiry
  contains the damage.
- **CSRF**: not applicable — endpoint takes the token in the body,
  not from a cookie.

---

## 7. Rate limiting

| Endpoint | Per-IP cap | Per-account cap | Why |
|---|---|---|---|
| `/api/auth/update` (when changing password) | 30/h | 5 wrong-current-password/h per user | Limits brute-force of `current_password` |
| `/api/auth/forgot-password` | 10/h per IP | 3/h per email | Prevents email-spam attacks where attacker triggers thousands of reset emails to a victim |
| `/api/auth/reset-password` | 10/h per IP | — | Limits brute-force of `token` field (already protected by 256-bit entropy + 15-min expiry, but defense in depth) |

Return `429 Too Many Requests` with `Retry-After: <seconds>` on
all of these.

---

## 8. End-to-end curl test cases

### 8.1 Change password — happy path

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{"password":"newSecret123","current_password":"oldSecret"}'

# Expect: 200, response.user present, response.token contains a
#         FRESH JWT (iat after the request). The old JWT becomes
#         invalid because `users.session_revoked_at` was bumped.
```

### 8.2 Change password — wrong current password

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{"password":"newSecret123","current_password":"WRONG"}'

# Expect: 403 { "code": "INVALID_CURRENT_PASSWORD" }
```

### 8.3 Change password — missing current_password

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{"password":"newSecret123"}'

# Expect: 400 { "code": "MISSING_CURRENT_PASSWORD" }
```

### 8.4 Change password — name update (unrelated path, regression)

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{"name":"New Name"}'

# Expect: 200, current_password NOT required because no password
#         change is being made.
```

### 8.5 Forgot password — existing email

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/forgot-password \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com"}'

# Expect: 200 { "ok": true, "message": "If an account exists ..." }
#         Email is sent. Reset row appears in password_reset_tokens
#         with consumed_at=NULL, expires_at=NOW()+15min.
```

### 8.6 Forgot password — non-existing email

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/forgot-password \
  -H 'Content-Type: application/json' \
  -d '{"email":"nope@nope.com"}'

# Expect: 200 with the SAME body as §8.5. No DB row written.
#         Response time should be within 100 ms of §8.5's response
#         time (no timing leak).
```

### 8.7 Reset password — happy path

```bash
# Take the raw token from the email (§8.5):
curl -k -X POST https://192.168.1.20:3001/api/auth/reset-password \
  -H 'Content-Type: application/json' \
  -d '{
    "token":    "<RAW_TOKEN>",
    "password": "brandNewPassword"
  }'

# Expect: 200, response.token = fresh JWT, response.user present.
#         password_reset_tokens row now has consumed_at = NOW().
#         users.password_hash updated. users.session_revoked_at
#         bumped.
```

### 8.8 Reset password — re-use already-consumed token

```bash
# Re-run §8.7 with the same token:
curl -k ... -d '{"token":"<SAME_TOKEN>","password":"another"}'

# Expect: 400 { "code": "TOKEN_ALREADY_USED" }
```

### 8.9 Reset password — expired token

```bash
# Wait 16 minutes after §8.5, then try:
curl -k ... -d '{"token":"<TOKEN_FROM_8_5>","password":"x"}'

# Expect: 400 { "code": "TOKEN_EXPIRED" }
```

### 8.10 Reset password — totally invalid token

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/reset-password \
  -H 'Content-Type: application/json' \
  -d '{"token":"deadbeef","password":"newSecret"}'

# Expect: 400 { "code": "TOKEN_INVALID" }
```

### 8.11 Session revocation — old JWT after password change

```bash
# Use the JWT from BEFORE §8.1 (it was valid then):
curl -k https://192.168.1.20:3001/api/auth/me \
  -H "Authorization: Bearer $OLD_JWT"

# Expect: 401 { "code": "SESSION_REVOKED" }
#         (or whatever code your existing JWT middleware uses for
#         "valid signature but session was revoked")
```

---

## 9. Roll-out order

Additive on the existing API. Ship in this order so the Flutter
client always has a valid path:

1. **Run the migration** — `password_reset_tokens` table +
   `users.session_revoked_at` column.
2. **Add `/api/auth/forgot-password` and `/api/auth/reset-password`
   endpoints.** They can ship on their own; the Flutter side
   shows the "Forgot password?" link the moment they're live.
3. **Extend `/api/auth/update`** to require `current_password` when
   `password` is present. Must ship at the same time as the
   matching Flutter release (the current sheet doesn't yet send
   `current_password`, so an early backend deploy would break the
   change-password flow for all current users until the app
   updates).
4. **Run the test cases in §8.**
5. **Email template review** with whoever owns the marketing /
   transactional email pipeline — see §10.

---

## 10. Email template — `/api/auth/forgot-password`

Plain text + HTML. Don't get fancy.

### Subject

`Reset your Mizdah password`

### Plain-text body

```
Hi {{firstName | "there"}},

We received a request to reset the password for the Mizdah account
attached to {{email}}.

If this wasn't you, you can safely ignore this email — your
password won't change.

If it was you, use the link below to set a new password. The link
expires in 15 minutes and can only be used once.

  {{resetUrl}}

Thanks,
The Mizdah team
```

### HTML body

Match your existing transactional-email template if you have one;
otherwise the plain text above wrapped in `<p>` tags is fine.

### Important

- `From:` must be a verified domain (`noreply@mizdah.app` or
  similar). Anti-spam scoring punishes random sender domains.
- `Reply-To:` should be a real support inbox so users with
  questions get human help, not a bounce.
- `resetUrl` placeholder is the deep-link URL —
  `https://mizdah.app/reset-password?token=<RAW_TOKEN>` (or your
  prod equivalent). The Flutter client's `LinkPhoneScreen` and
  similar code already opens these URLs via the OS share sheet /
  url_launcher.

---

## 11. Security notes — the short version

| Concern | Mitigation |
|---|---|
| Stolen JWT used to change password | §3 `current_password` requirement blocks it. |
| Email enumeration via forgot-password | §4.2 always-200 + timing-safe response. |
| Brute-force the current_password | §7 rate-limit (5 wrong/h per user). |
| Brute-force the reset token | 256 bits of entropy + 15-min expiry + single-use + §7 rate-limit. |
| Leaked email log replays | Token stored as hash, not plaintext; old emails worthless after consumed_at or expires_at. |
| Race: two reset emails issued back-to-back | §4.2 invalidates previous unconsumed tokens. |
| Session-fixation after compromise | §5.3 + §2.2 `session_revoked_at` invalidates all other JWTs. |
| Self-DoS via reset spam to a target | §7 per-email cap (3/h). |

---

## 12. Future polish / open items

| Item | Status | Notes |
|---|---|---|
| Audit log table for password changes + resets | OPTIONAL | A `security_events` table with rows for `password_changed_by_user` / `password_reset_completed` etc. helps incident response. |
| Email notification to user "your password was just changed" | RECOMMENDED for v2 | Sent on every successful change/reset. Even if the change was malicious, this is the user's chance to react. |
| Re-auth before sensitive operations (delete account, change email) | OUT OF SCOPE for this doc | But the `password_changed_at` column added here makes it easy to require "must have authenticated in the last 5 min" later. |
| Push notification on password change | OPTIONAL | Same intent as the email. |

---

## TL;DR for the backend dev

| Task | Effort |
|---|---|
| §2 `password_reset_tokens` table + nightly cleanup | 20 min |
| §2.2 `users.session_revoked_at` column + JWT middleware tweak | 15 min |
| §3 Extend `/api/auth/update` with current-password verification + session revocation | 30 min |
| §4 New `POST /api/auth/forgot-password` (incl. SHA-256 hash, email send, timing-safe response) | 45 min |
| §5 New `POST /api/auth/reset-password` | 45 min |
| §6 Token generation utility + hashing helper | 15 min |
| §7 Per-user / per-IP rate limits | 15 min |
| §8 Test cases automated | 30 min |
| §10 Email template review | 15 min |
| **Total** | **~3 hours** |

Questions / clarifications → ping the Flutter dev. Once shipped,
the Flutter side wires up:

- Current-password field on the Change password sheet (already
  spec'd visually in the previous reply).
- "Forgot password?" link on the login screen.
- New screen `/reset-password` that consumes the deep-link token
  + posts to §5.

Estimated Flutter follow-up: **~2 hours**.
