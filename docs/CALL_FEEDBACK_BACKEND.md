# Call / Meeting Feedback — Backend Spec

Tiny new endpoint that accepts a 1–5 star rating + optional issue
tags + optional comment after a P2P call or meeting ends. The
Flutter client gates the prompt itself (duration ≥ 30s, sampled at
~40% of eligible calls, max once per 24 h per user) so the
endpoint will see traffic at roughly **N×0.40 / 24 h** where N is
your daily eligible-call count. Plenty of headroom on a single
Postgres row write per request.

Total backend work: **~2 hours** (route + validation + table +
2 indexes + 4 curl test cases). One new endpoint, one new table,
nothing else.

---

## 0. Conventions

Same as the rest of the API docs in this folder:

- Gateway: `https://<dev-host>:3001` (dev),
  `https://mizdah-backend.ogoul.cloud` (prod).
- Auth: `Authorization: Bearer <JWT>` required.
- Bodies: `application/json`.
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.
- Timestamps: ISO-8601 UTC.

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| Add `call_ratings` table | DB | NEW |
| Endpoint `POST /api/feedback/call-rating` | new route | NEW |
| Validate closed-vocabulary tags | shared util | NEW |

No changes to any existing endpoint. Additive only.

---

## 2. Data model — new table

```sql
CREATE TABLE call_ratings (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- For P2P this is the callId UUID we generate client-side and round-
  -- trip through `initiate-call`. For meetings this is the meeting id.
  call_id           VARCHAR(64) NOT NULL,
  -- "p2p_audio" | "p2p_video" | "meeting"
  call_type         VARCHAR(16) NOT NULL,
  rating            SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  -- Closed vocabulary; see §4. Stored as TEXT[] so the on-call
  -- engineer can run `WHERE 'audio_echo' = ANY(tags)` queries.
  tags              TEXT[] NOT NULL DEFAULT '{}',
  comment           TEXT,
  duration_seconds  INTEGER NOT NULL CHECK (duration_seconds >= 0),
  rated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Idempotency: same user can't double-submit for the same call.
  -- An UPDATE path replaces the row (see §5).
  UNIQUE (user_id, call_id)
);

-- "What did I rate yesterday?" lookup by user.
CREATE INDEX call_ratings_user_idx
  ON call_ratings (user_id, rated_at DESC);

-- "What went wrong this week?" — partial index for the on-call
-- engineer's primary query, much smaller than a full index on
-- `rated_at` because low-rating rows are the minority.
CREATE INDEX call_ratings_low_idx
  ON call_ratings (rated_at DESC)
  WHERE rating <= 2;
```

`ON DELETE CASCADE` so account deletion drops the feedback too.
Optional — if your retention policy says keep feedback after
account deletion, drop the cascade.

---

## 3. Endpoint — `POST /api/feedback/call-rating`

### 3.1 Request

```jsonc
POST /api/feedback/call-rating
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "callId":           "1b8d2264-1911-44ef-a7f9-538d5bba9b63",
  "callType":         "p2p_video",          // see §3.3
  "rating":           2,                    // 1..5
  "tags":             ["audio_echo"],       // optional, may be []
  "comment":          "My peer's audio kept cutting.",  // optional
  "durationSeconds":  252,
  "ratedAt":          "2026-05-14T08:30:00Z"  // client clock
}
```

### 3.2 Validation rules

In order. Fail the first that doesn't pass with the matching 400
code:

| # | Rule | Failure code |
|---|---|---|
| 1 | `callId` present, non-empty, ≤64 chars | `BAD_REQUEST` |
| 2 | `callType` ∈ `{p2p_audio, p2p_video, meeting}` | `BAD_REQUEST` |
| 3 | `rating` is integer in `[1, 5]` | `BAD_REQUEST` |
| 4 | `tags` is an array of ≤8 strings | `BAD_REQUEST` |
| 5 | Every `tags[i]` is in the closed vocabulary (§4) | `INVALID_TAG` |
| 6 | `comment` is null or string with length ≤500 | `BAD_REQUEST` |
| 7 | `durationSeconds` ≥ 0 and ≤ 86400 | `BAD_REQUEST` |
| 8 | `ratedAt` is a parseable ISO-8601 timestamp | `BAD_REQUEST` |

`ratedAt` is the client's clock; clamp it server-side to
`min(now, ratedAt)` before writing so a wrong device clock can't
post-date a row.

### 3.3 `callType` values

| Value | Meaning |
|---|---|
| `p2p_audio` | An audio-only P2P call (no video tracks) |
| `p2p_video` | A video P2P call |
| `meeting` | An SFU meeting (any number of participants) |

Backend doesn't need to enforce that `callId` actually exists in
the calls / meetings table — feedback can outlive the call row,
and a strict reference would force a JOIN on every insert. The
analytics layer can do that reconciliation later.

### 3.4 Response — success

```jsonc
HTTP/1.1 200 OK
{ "ok": true }
```

That's it. No echoed payload, no row id — the client doesn't need
either.

### 3.5 Response — errors

| HTTP | `code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | Any structural / range violation |
| 400 | `INVALID_TAG` | Tag isn't in the §4 vocabulary |
| 401 | (standard) | Missing / expired token |
| 429 | `RATE_LIMITED` | Per-user cap (§6) tripped |
| 500 | `INTERNAL` | Server crash |

The Flutter client treats anything other than 200 as a silent
failure — feedback is fire-and-forget telemetry, never blocks the
user. So error response *bodies* don't need to be friendly; the
user never sees them.

---

## 4. Tag vocabulary (closed)

Strings in this list and nothing else. Anything else → 400
`INVALID_TAG`. New tags are added by editing this list + bumping
a backend release; intentional gate to keep analytics clean.

```
audio_echo
audio_muffled
audio_dropped
no_remote_audio
video_frozen
video_pixelated
video_dropped
no_remote_video
connection_failed
disconnected_mid_call
other
```

The Flutter side renders these as chips in the order listed.
Friendly labels live client-side (`Audio echo`, `My peer froze`,
etc.) so backend can change the wire spelling without a client
release.

---

## 5. Idempotency — `UNIQUE (user_id, call_id)`

If the client retries (flaky network, app foreground/background
race, etc.) the second `INSERT` violates the unique constraint.
Handle it as an UPDATE so the latest submission wins:

```sql
INSERT INTO call_ratings
  (user_id, call_id, call_type, rating, tags, comment,
   duration_seconds, rated_at)
VALUES
  ($1, $2, $3, $4, $5, $6, $7, LEAST(NOW(), $8::timestamptz))
ON CONFLICT (user_id, call_id) DO UPDATE SET
  rating           = EXCLUDED.rating,
  tags             = EXCLUDED.tags,
  comment          = EXCLUDED.comment,
  duration_seconds = EXCLUDED.duration_seconds,
  rated_at         = LEAST(NOW(), EXCLUDED.rated_at);
```

Why upsert and not 409: from the user's perspective the submit
succeeded — they shouldn't get a hostile response just because
the previous request also went through. Letting the latest
submission win matches what a user expects from "edit my rating".

---

## 6. Rate limiting

A user prompting fatigue cap already lives in the Flutter client
(max one prompt every 24 h, sampled at 40% of eligible calls).
The backend just needs a defensive cap to catch a malicious /
broken client that submits in a tight loop:

| Layer | Cap |
|---|---|
| Per-user | 60 / hour |
| Per-IP | 600 / hour |

Realistic users will land at <5/day; 60/h is generous. Return
`429 Too Many Requests` with `Retry-After: <seconds>` when hit.

No body-size cap needed beyond the standard JSON parser's default
(comment is the only free-form field and it's capped at 500
chars).

---

## 7. End-to-end curl test cases

### 7.1 Happy path — 5-star rating

```bash
curl -k -X POST https://192.168.1.20:3001/api/feedback/call-rating \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "callId":          "test-call-1",
    "callType":        "p2p_audio",
    "rating":          5,
    "tags":            [],
    "comment":         null,
    "durationSeconds": 180,
    "ratedAt":         "2026-05-14T08:30:00Z"
  }'

# Expect: 200 { "ok": true }
```

### 7.2 Low-rating with tags + comment

```bash
curl -k -X POST https://192.168.1.20:3001/api/feedback/call-rating \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "callId":          "test-call-2",
    "callType":        "p2p_video",
    "rating":          1,
    "tags":            ["audio_echo", "video_frozen"],
    "comment":         "Whole call was rough.",
    "durationSeconds": 92,
    "ratedAt":         "2026-05-14T08:32:00Z"
  }'

# Expect: 200, and:
#   SELECT * FROM call_ratings WHERE call_id = 'test-call-2';
#   shows tags = {audio_echo, video_frozen}.
```

### 7.3 Idempotency — re-submit overwrites

```bash
# Re-submit §7.2 with different rating and tags:
curl -k ... -d '{
    "callId":          "test-call-2",
    "callType":        "p2p_video",
    "rating":          3,
    "tags":            [],
    "comment":         null,
    "durationSeconds": 92,
    "ratedAt":         "2026-05-14T08:33:00Z"
  }'

# Expect: 200. After:
#   SELECT rating, tags FROM call_ratings WHERE call_id = 'test-call-2';
#   shows rating=3, tags={}.
```

### 7.4 Bad tag → 400 INVALID_TAG

```bash
curl -k -X POST https://192.168.1.20:3001/api/feedback/call-rating \
  -H "Authorization: Bearer $JWT" \
  -H 'Content-Type: application/json' \
  -d '{
    "callId":"test-call-3","callType":"meeting","rating":2,
    "tags":["totally_made_up"],"comment":null,
    "durationSeconds":120,"ratedAt":"2026-05-14T08:34:00Z"
  }'

# Expect: 400 { "code": "INVALID_TAG", "error": "..." }
```

### 7.5 Out-of-range rating → 400 BAD_REQUEST

```bash
curl -k ... -d '{
    "callId":"test-call-4","callType":"meeting","rating":7,
    "tags":[],"comment":null,
    "durationSeconds":120,"ratedAt":"2026-05-14T08:35:00Z"
  }'

# Expect: 400 { "code": "BAD_REQUEST" }
```

---

## 8. Roll-out order

Trivially additive — ship in one go:

1. **Run the migration** (§2).
2. **Add the route + validation** (§3).
3. **Deploy.**
4. **Run the test cases** in §7 against the dev gateway.
5. **Ping the Flutter dev** — once green, the Flutter side wires
   up the trigger points and the bottom sheet.

No client release is gated on this — until the Flutter side
ships the prompt, the endpoint just sits idle.

---

## 9. Why these specific choices (one-liners)

- **Closed tag vocabulary** → clean GROUP BY analytics; future
  product changes don't break old data.
- **Comment cap 500 chars** → rules out abuse, large enough for
  honest detail. Matches the form's character counter on the
  Flutter side.
- **`(user_id, call_id)` unique + upsert** → retries are safe,
  the user gets to "edit" their rating implicitly.
- **Partial index on low ratings** → on-call query is fast, full
  index would be 5–10× bigger for no extra value.
- **No reference constraint to calls/meetings table** → feedback
  outlives the parent row; saves a join on every write.
- **Soft cap at 60/h per user** → defensive; real users land
  under 5/day.

---

## TL;DR for the backend dev

| Task | Effort |
|---|---|
| §2 Migration (table + 2 indexes) | 15 min |
| §3 Route handler + validation | 45 min |
| §4 Tag-vocabulary constant + validator | 15 min |
| §5 Upsert query | 15 min |
| §6 Per-user/IP rate limit | 15 min |
| §7 Test cases automated | 15 min |
| **Total** | **~2 hours** |

Questions / clarifications → ping the Flutter dev. Once shipped,
say the word and I'll wire up the Flutter side (~6 h).
