# Phone Numbers + Contacts Sync — Backend Spec

This doc covers everything the backend needs to ship for the
WhatsApp-style "find your friends on Mizdah" feature being built in the
Flutter app. Three things tie together:

1. **Phone number captured at signup** and stored on the user.
2. **Bulk contacts-match endpoint** that takes phone numbers + emails and
   returns which of them belong to existing Mizdah users.
3. **Search extension** so the existing user search also matches phone.

Once these land, the Flutter side ships:

- A merged "Mizdah contacts" list in the Call tab (synced from the device
  address book → matched against the new endpoint).
- An "Invite to Mizdah" affordance for device contacts that aren't on
  Mizdah yet.
- Search results that distinguish registered users (with call buttons)
  from device contacts (with an Invite button).

Total backend surface area: **one new endpoint, two extensions, one
column added to the users table, one new index.**

---

## 0. Conventions used in this doc

- All endpoints are on the same gateway as the rest of the API
  (`https://<dev-host>:3001` in dev, `https://mizdah-backend.ogoul.cloud`
  in prod).
- All requests carry the standard `Authorization: Bearer <JWT>` header
  unless explicitly marked "no auth".
- All bodies are `Content-Type: application/json`.
- Phone numbers are **always E.164** (e.g. `+919876543210`,
  `+14155552671`). No spaces, no dashes, no leading zero, leading `+`
  mandatory. See §6 for normalization rules.
- Timestamps are ISO-8601 UTC (`2026-05-14T11:23:00Z`).
- Error responses follow the existing convention used by the rest of the
  API: `{ "error": "human readable", "code": "MACHINE_READABLE" }` with
  the appropriate HTTP status.

---

## 1. Data model changes

### 1.1 Add columns to the `users` table

```sql
ALTER TABLE users
  ADD COLUMN phone         VARCHAR(20)  NULL,           -- E.164, e.g. +919876543210
  ADD COLUMN phone_country CHAR(2)      NULL;           -- ISO-3166-1 alpha-2, e.g. IN

-- Phone must be unique across active accounts. NULLs allowed so
-- existing accounts and signups where phone is skipped don't collide.
-- Use a partial / functional unique index so multiple NULLs stay legal.
CREATE UNIQUE INDEX users_phone_unique
  ON users (phone)
  WHERE phone IS NOT NULL;

-- Fast lookup for the /contacts/match endpoint. Match is the hot path
-- (every Mizdah user uploads ~200 phones every few hours), so this
-- index pays for itself within minutes of going live.
CREATE INDEX users_phone_idx ON users (phone);
```

Field constraints:

| Column          | Type        | Nullable | Notes |
|-----------------|-------------|----------|-------|
| `phone`         | `VARCHAR(20)` | yes    | E.164 only. Max length 16 incl. `+`; varchar(20) leaves headroom. |
| `phone_country` | `CHAR(2)`   | yes      | ISO 3166-1 alpha-2 (`IN`, `US`, etc.). Stored separately so a phone whose country prefix is ambiguous can still be re-validated later. |

### 1.2 Migration for existing users

Existing accounts don't have a phone — `NULL` is fine. The Flutter side
will eventually nudge legacy users to add a phone via the profile
screen, but that's a v2 concern. For now: no backfill required.

---

## 2. Endpoint — extend `POST /api/auth/signup`

### 2.1 Request

```
POST /api/auth/signup
Content-Type: application/json
(no auth — public endpoint)

{
  "name":     "Alice Example",
  "email":    "alice@example.com",
  "password": "hunter2",
  "phone":    "+919876543210",       // NEW — required
  "phone_country": "IN"              // NEW — required, ISO alpha-2
}
```

### 2.2 Validation

Add the following before the existing email/password validation runs:

1. `phone` is required, non-empty after trim.
2. `phone` must match the E.164 regex `^\+[1-9]\d{6,14}$`.
3. `phone_country` is required, length exactly 2, uppercase ASCII.
4. The country code embedded in `phone` (the leading digits before the
   national number) **must be consistent** with `phone_country`. The
   easiest way is to parse with `libphonenumber` server-side — if you
   already have a phone library you trust, use it; otherwise the
   `phonenumbers` Python package or `libphonenumber-js` for Node.js
   both work. Reject with `INVALID_PHONE_COUNTRY` on mismatch.
5. The phone must not already belong to another active account.
   Look up by `phone` (unique index from §1.1). On hit, return 409.

### 2.3 Response (success)

Existing shape with `phone` added:

```jsonc
HTTP/1.1 201 Created
{
  "user": {
    "id":        "usr_01...",
    "email":     "alice@example.com",
    "name":      "Alice Example",
    "avatar_url": null,
    "role":      "USER",
    "phone":     "+919876543210",     // NEW
    "phone_country": "IN"             // NEW
  },
  "token": "<JWT>"
}
```

### 2.4 Error responses

| HTTP | `code`                  | When |
|------|--------------------------|------|
| 400  | `INVALID_PHONE`          | phone missing, malformed, or fails E.164 |
| 400  | `INVALID_PHONE_COUNTRY`  | `phone_country` missing, malformed, or doesn't match the dialing prefix of `phone` |
| 409  | `PHONE_ALREADY_TAKEN`    | phone is already in use by another account |
| 409  | `EMAIL_ALREADY_TAKEN`    | (existing) email already in use |
| 400  | `WEAK_PASSWORD`          | (existing) password rules failed |

Order of checks: validate phone **before** writing anything. If both
email and phone are taken, return the first one encountered — the
client retries once per error.

---

## 3. Endpoint — extend `POST /api/auth/update` (profile edit)

Optional but recommended for v1. Currently `/api/auth/update` accepts
name + password + avatar. Add phone support so users can fix a typo
or change carriers without contacting support.

### 3.1 Request additions

```jsonc
POST /api/auth/update
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "phone":         "+919876543299",     // optional; only present when changed
  "phone_country": "IN"                  // required if phone is present
}
```

Same validation as §2.2 items 1–5 (treating the *new* phone as the one
under test; uniqueness check excludes the calling user's own row).

### 3.2 Response

Same as the existing `/api/auth/update` — return the updated user object
including the new `phone` and `phone_country`.

---

## 4. Endpoint — NEW `POST /api/users/contacts/match`

This is the hot path. Every Mizdah user's app, after permission, uploads
a deduped list of their device contacts. The backend returns which of
those phones (and emails) map to existing Mizdah users.

### 4.1 Request

```jsonc
POST /api/users/contacts/match
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "phones": [
    "+919876543210",
    "+919812345678",
    "+14155552671"
  ],
  "emails": [
    "bob@example.com",
    "carol@example.org"
  ]
}
```

Constraints:

- `phones` is required (may be empty), max **500 entries per request**.
  Client batches if their address book is bigger.
- `emails` is optional, max **500 entries per request**.
- All phone strings must be valid E.164. Server **silently drops**
  invalid entries from the lookup (do NOT reject the whole request —
  one bad number shouldn't kill the sync; just log and skip).
- Total request body size cap: **256 KB**. Reject larger with 413.

### 4.2 Response

```jsonc
HTTP/1.1 200 OK
{
  "matches": [
    {
      "matchedBy":  "phone",                       // "phone" | "email"
      "matchedValue": "+919876543210",
      "userId":     "usr_01HX...",
      "name":       "Bob Bobson",
      "email":      "bob@example.com",
      "phone":      "+919876543210",
      "avatar_url": "https://cdn.mizdah.app/avatars/abc.jpg"
    },
    {
      "matchedBy":  "email",
      "matchedValue": "carol@example.org",
      "userId":     "usr_01HY...",
      "name":       "Carol",
      "email":      "carol@example.org",
      "phone":      "+919812345678",
      "avatar_url": null
    }
  ],
  "stats": {
    "phones_submitted": 3,
    "emails_submitted": 2,
    "phones_dropped":   0,    // failed E.164 validation
    "emails_dropped":   0,
    "matches_found":    2
  }
}
```

### 4.3 Match semantics

For each phone in the request, look up `users.phone == phone` (exact
match — we already normalized to E.164 client-side and server-side
re-validates). Skip blocked / deleted users.

For each email in the request, look up `users.email == email` (case-
insensitive). Same skip-rules.

**Deduping:** if a phone match AND an email match resolve to the SAME
`userId`, return ONE entry with `matchedBy: "phone"` (phone wins —
it's the higher-confidence signal because users can't share phones but
can share emails).

**Privacy:** never return phones / emails that did NOT have a match.
The response leaks *only* the values the requester already knows.

### 4.4 Rate limiting

This endpoint is the easiest abuse vector in the whole API — a
malicious client can iterate through phone-number ranges to enumerate
who's on Mizdah. Mitigations:

| Layer            | Cap                                                         |
|------------------|-------------------------------------------------------------|
| Per token        | **100 requests/hour** with **500 entries each** = 50k/hr    |
| Per IP           | 500 requests/hour                                           |
| Per-account hard | Total entries lifetime soft-capped at 10,000 unique phones; beyond that, return 429 with hint to wait. |

A reasonable cold-start user has ~200 contacts. They'll do 1 request on
sign-in and an incremental request every 6 hours. 100/hr is generous.

Return `429 Too Many Requests` with `Retry-After: <seconds>`.

### 4.5 Error responses

| HTTP | `code`               | When |
|------|----------------------|------|
| 400  | `BAD_REQUEST`        | body shape wrong (e.g. `phones` not an array) |
| 401  | (standard)           | missing / expired token |
| 413  | `PAYLOAD_TOO_LARGE`  | body > 256 KB |
| 429  | `RATE_LIMITED`       | per-IP / per-token / lifetime cap hit |
| 500  | `INTERNAL`           | server crash |

### 4.6 Implementation notes

- This is a **read-only** endpoint. Should be safe to serve from a
  replica DB.
- Don't log the request body in plaintext — phones are PII. Log
  `phones_submitted` count + `userId` + `request_id` only.
- Match queries should use the new `users_phone_idx`. Profile with a
  500-entry request to confirm latency stays under 200ms p95.

---

## 5. Endpoint — extend `GET /api/auth/users/search`

Already exists. Today it matches by email and name. Make it ALSO match
by phone, so the search bar in the Call tab gives one result for
"+91987..." just like it does for "alice@".

### 5.1 Request (unchanged)

```
GET /api/auth/users/search?q=<query>
Authorization: Bearer <JWT>
```

### 5.2 New matching rules

When `q`:

1. Starts with `+` and the remaining characters are all digits →
   treat as a phone search. Match `users.phone == q` (exact). Return
   at most 1 result.
2. Contains `@` → email search (existing behaviour).
3. Otherwise → name search (existing behaviour, prefix/substring).

Don't fall through across types — a phone search should NOT also try
name matching. Avoids surprising "+91" matching anyone with `+91` in
their display name.

### 5.3 Response (unchanged shape, add phone)

```jsonc
HTTP/1.1 200 OK
{
  "users": [
    {
      "id":         "usr_01...",
      "name":       "Alice",
      "email":      "alice@example.com",
      "phone":      "+919876543210",     // NEW
      "avatar_url": null
    }
  ]
}
```

Phone field can be `null` for users created before §1.1 ran in prod.

---

## 6. Phone-number normalization rules

Both client and server normalize independently. The server is the
authority — if client and server disagree, server's value wins. Rules:

1. **Strip everything that isn't a digit or leading `+`.**
   `+91 98765 43210` → `+919876543210`
   `(415) 555-2671` → `4155552671` (no `+`, treated as ambiguous)
2. If the result doesn't start with `+`:
   - Treat the user's `phone_country` (or signup country) as the
     default region.
   - Run through `libphonenumber.parse(s, region)` to get a `+CC` form.
3. **Validate** with `libphonenumber.isValidNumber(...)`. Reject if not.
4. **Canonical form**: `libphonenumber.format(NUMBER, E164)`. This is
   what gets stored and what the client uploads.

Use `libphonenumber` (the Google library — bindings exist for every
backend language). Don't roll your own; phone formats are a swamp.

Test cases to confirm:

| Input                      | Region | Output            | Valid? |
|----------------------------|--------|-------------------|--------|
| `9876543210`               | IN     | `+919876543210`   | yes    |
| `+91 98765-43210`          | (any)  | `+919876543210`   | yes    |
| `09876543210`              | IN     | `+919876543210`   | yes    |
| `+14155552671`             | (any)  | `+14155552671`    | yes    |
| `4155552671`               | US     | `+14155552671`    | yes    |
| `123`                      | IN     | —                 | no     |
| `00919876543210`           | IN     | `+919876543210`   | yes    |
| empty / spaces-only        | IN     | —                 | no     |

---

## 7. Privacy + security checklist

The contacts endpoint touches PII. Before going live:

- [ ] **Don't log request bodies.** Only counts + request IDs.
- [ ] **Don't store the upload.** It's request-scoped — match, respond,
      discard. No "contacts you've ever uploaded" table.
- [ ] **TLS-only.** No fallback to HTTP under any flag.
- [ ] **JWT required.** No public path for the match endpoint.
- [ ] **Rate-limit deployed before launch.** Without §4.4 the endpoint
      is an enumeration oracle.
- [ ] **Soft-delete users are excluded** from `matches`. A user who
      deletes their account should disappear from everyone else's
      synced contacts on the next refresh.
- [ ] **Block-list respected.** If user A has blocked user B, B's
      `match` requests should NOT return A (and vice-versa). If the
      block model doesn't exist yet, this can wait — flag it.
- [ ] **PII in DB encrypted at rest.** Standard already-deployed
      protection; just confirm phone isn't logged via DB triggers.
- [ ] **Add an "I don't want to be findable by phone" toggle** to the
      profile (v2, not blocking). When set, the user is excluded from
      `match` results.

---

## 8. End-to-end test cases for the backend dev

Run these against the dev environment before handing off:

### 8.1 Signup happy path
```
curl -k -X POST https://192.168.1.20:3001/api/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"T1","email":"t1@example.com","password":"hunter22",
    "phone":"+919876543210","phone_country":"IN"
  }'
# expect: 201, response.user.phone == "+919876543210"
```

### 8.2 Signup with duplicate phone
```
# Run §8.1 then run again with different email but same phone
# expect: 409 { "code": "PHONE_ALREADY_TAKEN" }
```

### 8.3 Match — hit on phone
```
curl -k -X POST https://192.168.1.20:3001/api/users/contacts/match \
  -H 'Authorization: Bearer $JWT' \
  -H 'Content-Type: application/json' \
  -d '{"phones":["+919876543210","+919999999999"],"emails":[]}'
# expect: 200, matches has 1 entry with matchedValue="+919876543210"
```

### 8.4 Match — hit on email
```
curl -k -X POST https://192.168.1.20:3001/api/users/contacts/match \
  -H 'Authorization: Bearer $JWT' \
  -H 'Content-Type: application/json' \
  -d '{"phones":[],"emails":["t1@example.com"]}'
# expect: 200, matches has 1 entry with matchedBy="email"
```

### 8.5 Match — dedupe across phone and email
```
# Submit both phone and email of the same user
curl ... -d '{"phones":["+919876543210"],"emails":["t1@example.com"]}'
# expect: matches has exactly 1 entry, matchedBy="phone"
```

### 8.6 Match — invalid phones are dropped, not 400
```
curl ... -d '{"phones":["+919876543210","not a number","+1"],"emails":[]}'
# expect: 200, stats.phones_dropped == 2, matches.length == 1
```

### 8.7 Match — over the size cap
```
# 501 phones in the request
# expect: 400 { "code":"BAD_REQUEST" } describing 500-entry cap
```

### 8.8 Search — phone match
```
curl -k -G https://192.168.1.20:3001/api/auth/users/search \
  --data-urlencode 'q=+919876543210' \
  -H 'Authorization: Bearer $JWT'
# expect: users array has 1 entry, that exact user
```

### 8.9 Search — email match (regression)
```
curl ... --data-urlencode 'q=t1@example.com'
# expect: unchanged behaviour from today
```

### 8.10 Search — name match (regression)
```
curl ... --data-urlencode 'q=T1'
# expect: unchanged behaviour from today
```

---

## 9. Roll-out order

Deploy in this sequence so the Flutter client doesn't break:

1. **DB migration (§1.1)** — additive, no downtime. Safe to run any
   time; existing rows just get `phone = NULL`.
2. **Search extension (§5)** — additive (one new code path for `q`
   starting with `+`). Safe.
3. **Match endpoint (§4)** — new endpoint, zero impact on existing
   clients.
4. **Signup extension (§2)** — this one's NOT backward compatible
   from the server's perspective because the new fields are
   **required**. Coordinate the cutover:
   - Backend deploys §2 with phone fields **optional** for ~1 week.
   - Flutter client ships requiring phone fields.
   - After clients have rolled out, backend flips phone fields to
     required (rejects signups without them).
   OR
   - Backend ships phone fields as required immediately, but Flutter
     stages the release so old clients can't sign up — typically too
     aggressive; the soft cutover above is safer.

---

## 10. Open questions for the Flutter side

These don't block backend work but flag here so the API contract above
gets revisited if any decision goes the other way:

- **Phone format on display** — the Flutter client uploads E.164 and
  displays whatever the device address-book has. No server change
  required either way.
- **"Findable by phone" toggle** — pre-emptively reserve a column
  (`phone_searchable BOOLEAN DEFAULT TRUE`) so adding the toggle later
  doesn't need a migration?
- **Phone OTP verification** — out of scope for v1. The phone gets
  stored on signup but isn't verified. If anti-spam becomes a concern,
  add an OTP flow before §4 goes live. The Flutter side doesn't ask
  for OTP today.

---

## 11. Contacts (just so it's documented somewhere)

The Flutter side does NOT send raw device-contact data anywhere except
to `/api/users/contacts/match`. Specifically:

- **What's uploaded:** deduped E.164 phone strings + deduped emails.
- **What's NOT uploaded:** contact display names, photos, addresses,
  notes, organization, relationship, IM handles, anything else
  `flutter_contacts` returns.
- **Where it goes:** straight to `/contacts/match`, response cached
  locally in SharedPreferences, raw uploaded data is discarded the
  moment the response comes back.
- **How often:** on first login after permission grant, on Call-tab
  open if last sync > 6h ago, on pull-to-refresh.

The backend doesn't need to do anything with this — just listed for
completeness so security review knows the scope.

---

## TL;DR for the backend dev

| Task | Effort |
|---|---|
| §1 DB migration (add `phone` + `phone_country` + 2 indexes) | 1h |
| §2 Extend `/api/auth/signup` to accept + validate phone | 2-3h |
| §3 (optional) Extend `/api/auth/update` for phone changes | 1h |
| §4 New `/api/users/contacts/match` (incl. rate limit) | 4-6h |
| §5 Extend `/api/auth/users/search` to match phone | 1h |
| §6 libphonenumber wired into validation utilities | 2h |
| §7 Privacy/security review + checklist | 1h |
| §8 Test cases automated | 2h |
| **Total** | **~2 days** |

Questions / clarifications → ping the Flutter dev; we'll cut a follow-up
revision of this doc if the API contract needs to flex.
