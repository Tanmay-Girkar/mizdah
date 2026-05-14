# Link Phone Number — Backend Spec (no OTP)

Companion doc to [PHONE_AND_CONTACTS_BACKEND.md](./PHONE_AND_CONTACTS_BACKEND.md).
That one covers **new signups** which now require a phone. This one
covers **existing accounts** (2M+ users currently on the platform
without any phone on file) that need a way to *add* a phone after the
fact, from the Settings screen.

The flow is intentionally simple: **no OTP, no SMS, no verification
loop**. The user types a phone, taps Save, the backend stores it.
This was a product decision — see §7 for the tradeoff.

Total backend work: **~2 hours** if the DB migration from
[PHONE_AND_CONTACTS_BACKEND.md §1](./PHONE_AND_CONTACTS_BACKEND.md)
has already shipped. **Zero new endpoints** — this is a small
extension to the already-existing `POST /api/auth/update`.

---

## 0. Conventions

Same as the parent doc:

- Gateway: `https://<dev-host>:3001` in dev,
  `https://mizdah-backend.ogoul.cloud` in prod.
- Auth: `Authorization: Bearer <JWT>` required.
- Bodies: `Content-Type: application/json`.
- Phones: **E.164** (e.g. `+919876543210`).
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| Accept `phone` + `phone_country` on the profile-update endpoint | `POST /api/auth/update` | NEW — needs to be implemented |
| Validate the new phone the same way signup does (libphonenumber + uniqueness) | shared validation utility | NEW if not already centralized |
| Return the updated user object with the new phone fields populated | response shape | unchanged shape, new fields populated |

Nothing else. No new tables, no new columns, no new endpoints.

---

## 2. Endpoint — extend `POST /api/auth/update`

### 2.1 Today's behaviour (do not break)

The endpoint already accepts `name`, `password`, and `avatar_url`:

```jsonc
POST /api/auth/update
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "name":       "Alice Example",       // optional
  "password":   "hunter2new",           // optional
  "avatar_url": "https://cdn.../a.jpg"  // optional
}
```

Each field is independent; sending only one is valid. Keep that
behaviour. Just add two more accepted fields.

### 2.2 New behaviour — phone + phone_country

```jsonc
POST /api/auth/update
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "phone":         "+919876543210",   // NEW — optional
  "phone_country": "IN"               // NEW — required IF `phone` is present
}
```

Field rules:

| Field | Required | Constraints |
|---|---|---|
| `phone` | optional (the whole field can be omitted) | E.164 `^\+[1-9]\d{6,14}$`, must pass `libphonenumber.isValidNumber` |
| `phone_country` | required ONLY when `phone` is present | ISO-3166-1 alpha-2, uppercase, must be consistent with the dialing prefix of `phone` |

If both fields are absent, this endpoint behaves exactly as today.

### 2.3 Validation order (matters for clean errors)

When `phone` is present in the request:

1. Reject if missing/malformed → `400 INVALID_PHONE`.
2. Reject if `phone_country` is missing/malformed → `400 INVALID_PHONE_COUNTRY`.
3. Reject if the country code embedded in `phone` doesn't match
   `phone_country` → `400 INVALID_PHONE_COUNTRY`.
4. Check `users.phone == phone WHERE id != <calling user>`. Reject
   if hit → `409 PHONE_ALREADY_TAKEN`.
5. Otherwise: write `phone` and `phone_country` to the user's row.

Other fields (name / password / avatar) follow their existing
validation paths; phone validation runs **after** name/password
validation if those are present (no need to change order beyond
keeping phone checks together).

### 2.4 Response — success

Identical shape to today (the full updated user object), now with
the phone fields populated:

```jsonc
HTTP/1.1 200 OK
{
  "user": {
    "id":            "usr_01HX...",
    "email":         "alice@example.com",
    "name":          "Alice Example",
    "avatar_url":    null,
    "role":          "USER",
    "phone":         "+919876543210",     // NEW — was null before this call
    "phone_country": "IN",                // NEW
    // ... any other existing fields kept unchanged
  }
}
```

### 2.5 Response — errors

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID_PHONE` | `phone` missing/malformed/fails E.164 |
| 400 | `INVALID_PHONE_COUNTRY` | `phone_country` missing/malformed/mismatched |
| 401 | (standard) | missing/expired token |
| 409 | `PHONE_ALREADY_TAKEN` | phone is already in use by **another** active account |
| 500 | `INTERNAL` | server crash |

Note on the 409: the calling user's *own* current phone does **not**
trigger the conflict. A user re-saving the same phone they already
have should return 200 with the user object (no-op on the DB).

---

## 3. Phone normalisation rules

Identical to [PHONE_AND_CONTACTS_BACKEND.md §6](./PHONE_AND_CONTACTS_BACKEND.md).
Use `libphonenumber` (same library, same call sites). The Flutter
client sends a value already normalised to E.164 — the server
re-validates and stores the canonical form. Server's canonical form
wins on disagreement.

---

## 4. Database

Nothing new in this doc. The columns + indexes were added in
[PHONE_AND_CONTACTS_BACKEND.md §1](./PHONE_AND_CONTACTS_BACKEND.md)
when signup started accepting phones:

```sql
-- Already shipped:
ALTER TABLE users
  ADD COLUMN phone VARCHAR(20) NULL,
  ADD COLUMN phone_country CHAR(2) NULL;

CREATE UNIQUE INDEX users_phone_unique
  ON users (phone) WHERE phone IS NOT NULL;

CREATE INDEX users_phone_idx ON users (phone);
```

Confirm those are live in prod before rolling this endpoint out.

If you want to track *when* a user added their phone (for future
abuse analytics), add a nullable column now:

```sql
ALTER TABLE users
  ADD COLUMN phone_linked_at TIMESTAMPTZ NULL;
```

Update it in §2.3 step 5. Optional — not load-bearing.

---

## 5. Tied-in change — `searchUsers` already matches phone

[PHONE_AND_CONTACTS_BACKEND.md §5](./PHONE_AND_CONTACTS_BACKEND.md)
already specs that `GET /api/auth/users/search?q=<phone>` returns
users whose `phone` column matches. The moment this endpoint
stores a phone for an existing user, that user instantly becomes
findable by phone search AND by `/api/users/contacts/match`
uploads from other users. No extra wiring.

---

## 6. End-to-end test cases for the backend dev

Run these against the dev environment after the change ships. They
assume `$JWT` is a valid token for an account that does NOT yet
have a phone.

### 6.1 Link a phone for the first time

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "+919876543210",
    "phone_country": "IN"
  }'

# Expect: 200, response.user.phone == "+919876543210",
#         response.user.phone_country == "IN"
```

### 6.2 Re-save the same phone (idempotent no-op)

```bash
# Run §6.1 again with the same body.
# Expect: 200, same response. NOT 409 — calling user's own phone
#         doesn't conflict with itself.
```

### 6.3 Switch to a different phone

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "+919812345678",
    "phone_country": "IN"
  }'

# Expect: 200, response.user.phone == "+919812345678" (the old number
#         is overwritten — no separate unlink endpoint needed).
```

### 6.4 Try to claim a phone someone else owns

```bash
# Sign up a SECOND user (or use a known account) that has
# "+919999999999" as their phone. Then with the first user's JWT:

curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "+919999999999",
    "phone_country": "IN"
  }'

# Expect: 409 { "code": "PHONE_ALREADY_TAKEN" }
```

### 6.5 Invalid phone

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "123",
    "phone_country": "IN"
  }'

# Expect: 400 { "code": "INVALID_PHONE" }
```

### 6.6 Missing phone_country

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "+919876543210"
  }'

# Expect: 400 { "code": "INVALID_PHONE_COUNTRY" }
```

### 6.7 phone_country doesn't match dialing prefix

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "phone": "+919876543210",
    "phone_country": "US"
  }'

# Expect: 400 { "code": "INVALID_PHONE_COUNTRY" }
```

### 6.8 Update name + phone together (regression test)

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Alice Renamed",
    "phone": "+919876543210",
    "phone_country": "IN"
  }'

# Expect: 200, both name AND phone updated on the user.
```

### 6.9 Update password only (regression — must still work without phone)

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/update \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "password": "newpassword123"
  }'

# Expect: 200, password updated, phone unchanged.
```

---

## 7. Security tradeoff — why no OTP

The product call is to ship without OTP for speed. The Flutter side
mirrors this — the Settings → Link phone screen has no OTP input.

**The known abuse vector:** a user can claim any phone number, not
just their own. If user A claims `+91 98765 43210` (which is
actually user B's real number, but B hasn't joined Mizdah yet),
then B's friends — who have B saved in their address book — will
see user A surfaced as "the Mizdah account for that number" in
their Call tab.

This is mitigated to some extent by the uniqueness constraint in
§2.3 step 4: only one Mizdah account can claim a given phone at a
time. So the moment user B (the real owner) joins Mizdah and tries
to register / link the same number, they'll get 409. They can
contact support to release the squatted entry.

**If abuse becomes visible**, the upgrade path is documented in
[PHONE_AND_CONTACTS_BACKEND.md §7's "v2: findable-by-phone toggle"](./PHONE_AND_CONTACTS_BACKEND.md)
note + adding a `phone_verified_at` column populated only by an OTP
flow. Existing un-OTP'd users would be grandfathered as
unverified; the contacts/match endpoint would optionally filter
those out under a new query param like `?verified_only=true`.

This is not a v1 concern. Flagged here so the rollback plan is
documented.

---

## 8. Roll-out order

Trivially small, but for the record:

1. **Confirm DB columns exist** (from PHONE_AND_CONTACTS_BACKEND.md §1).
   No-op if already shipped.
2. **Extend `/api/auth/update` validation + write path.** Additive
   — adding two new optional fields to an existing endpoint does
   not break any existing client.
3. **Run the test cases in §6.**
4. **Cut the release.** No staged rollout needed; the Flutter client
   only sends the new fields when the user explicitly uses the new
   Settings screen, so there's no risk of old clients getting
   confused by the new fields.

Backend can ship this independently of the Flutter side — the
Flutter changes are non-breaking even if the backend hasn't shipped
yet (a save would just 400 with "Method Not Allowed" or similar
until backend lands, and users see an inline error).

---

## 9. Open items / future v2 notes

| Item | Status | Notes |
|---|---|---|
| OTP verification | DEFERRED | See §7. Add when abuse becomes visible. |
| `phone_linked_at` column | OPTIONAL | Helps later abuse analytics. |
| "Findable by phone" privacy toggle | DEFERRED | Same as parent doc §7. |
| `USER_NOT_FOUND` login error code | UNRELATED but related | The Flutter login screen would auto-route failed logins to the register page IF the backend returned a distinct code for "no such user". Currently returns `Invalid credentials` for both wrong-password and no-such-user. Cheap to add; out of scope here but worth bundling into the next backend release. |

---

## TL;DR for the backend dev

| Task | Effort |
|---|---|
| §2 Extend `/api/auth/update` to accept `phone` + `phone_country` | 1–2h |
| §6 Test cases automated | 30 min |
| (Optional) Add `phone_linked_at` column | 15 min |
| (Optional, bundle from §9) Add `USER_NOT_FOUND` login error code | 30 min |
| **Total** | **~2 hours**, plus 1 hour if you take the optionals |

Questions / clarifications → ping the Flutter dev.
