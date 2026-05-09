# P2P call history API — backend specification

Status: **Draft v1** — implement against this contract; the Flutter client is
already wired to this shape via `lib/features/call/data/call_log_models.dart`
and currently runs against a local SharedPreferences store. When this endpoint
ships, swap the impl behind `callLogRepositoryProvider` (in
`lib/features/call/call_log_provider.dart`) from `LocalCallLogRepository` to a
`RealCallLogRepository(ApiClient(), socketClient)` — UI doesn't change.

---

## Why this is its own service

Mizdah already has a `participant_history` service that records **meeting
participation** (who joined which meeting room, when, for how long). That data
powers the Recent Activity card on Home and the Recent list on Meetings.

P2P calls are a **separate concern**:

- They go through the **signaling** server (the socket events `incomingCall`,
  `acceptCall`, `declineCall`, `cancelCall`, `endCall`, `calleeOffline`).
- They have **terminal outcomes** that meetings don't have: declined, cancelled,
  failed, missed.
- They have a **peer** — a single specific user — not a meeting room.

Lumping them into `participant_history` would muddy both schemas. Keep them in
their own table.

---

## 1. Identity model

- Authentication is the existing Mizdah JWT (`Authorization: Bearer <token>`).
- Peer identity uses the existing `user_id` (UUID). The wire format also
  includes `peer_name` (resolved at log-write time) so the call log renders
  even if the peer is later deleted.
- All timestamps are ISO 8601 UTC.

---

## 2. REST endpoints

Base path: `/api/calls` (mount under the existing Express app).

### 2.1 List my call log

```
GET /api/calls/log?limit=100&before=<entry_id>
```

Reverse-cursor pagination by `started_at`. Newest first. `limit` is clamped
server-side to `[1, 200]`, default 100.

Response 200:
```json
{
  "entries": [
    {
      "id": "call_8f2a1c...",
      "peer_user_id": "uuid-of-other-side",
      "peer_name": "Alex Wong",
      "peer_email": "alex.wong@gmail.com",
      "started_at": "2026-05-09T12:30:11.000Z",
      "duration_seconds": 184,
      "direction": "outgoing",
      "outcome": "answered",
      "with_video": true
    }
  ],
  "has_more": true
}
```

`direction` ∈ `outgoing | incoming`.

`outcome` ∈ `answered | declined | missed | cancelled | failed`. Mapping:
- **answered** — both sides connected; `duration_seconds > 0`.
- **declined** — peer (or me, if incoming) tapped reject.
- **missed** — call rang out without being answered. From caller's perspective
  this is "no answer / offline"; from callee's perspective this is "I didn't
  pick up before they hung up."
- **cancelled** — caller hung up before the callee accepted. Only ever logged
  on the caller's side.
- **failed** — signaling / network error before media could connect.

### 2.2 Append an entry

```
POST /api/calls/log
Body:
{
  "id": "call_8f2a1c...",        // client-generated, see §3
  "peer_user_id": "...",
  "peer_name": "Alex Wong",
  "peer_email": "alex.wong@gmail.com",  // optional
  "started_at": "2026-05-09T12:30:11.000Z",
  "duration_seconds": 184,
  "direction": "outgoing",
  "outcome": "answered",
  "with_video": true
}
```

Idempotent on `id`. If the same id was already inserted, return the existing
row with 200; otherwise insert and return 201.

Response (200/201):
```json
{ "entry": { ...same shape as 2.1... } }
```

Server side-effects:
- Emit `call:logged` over the existing P2P signaling socket to the **peer's**
  online sessions, so their device picks up the corresponding incoming-side
  entry without having to write its own (see §3).
- Update aggregates (per-day count, total minutes) for analytics.

### 2.3 Clear my call log

```
DELETE /api/calls/log
```

Soft-delete (set `deleted_at`). Returned to me as empty going forward, but
retained for support / audit.

Response 204.

### 2.4 Optional — single-call detail

```
GET /api/calls/log/:id
```

Returns the single entry. Useful for deep-linking from a notification ("Marcus
called you" → opens the entry). 404 if not found / not yours.

---

## 3. Authoring flow — who writes the entry

Every P2P call attempt produces **one** entry. The question is who writes it
and when. The contract is:

1. **Caller side** writes the entry on every terminal outcome it observes:
   `declined` (peer rejected), `missed` (callee offline / no-answer),
   `cancelled` (I hung up first), `failed`, and `answered` (after `endCall`).
2. **Callee side** writes the entry on every terminal outcome it observes:
   `declined` (I rejected), `missed` (caller cancelled / rang out before I
   answered), and `answered` (after `endCall`).

To avoid double-writes at the table level, both sides use a deterministic id:

```
id = "call_" + sha1(callId + "_" + viewer_user_id).slice(0, 16)
```

Where `callId` is the same id the signaling server already issues for the call.
This guarantees:
- The caller's entry has a different id from the callee's entry (different
  `viewer_user_id`), so both sides have their own row.
- Re-attempts to write the same entry from the same viewer are dedup'd by `id`.

(The Flutter client today uses `callId` directly as the entry id because the
local store is per-device — when wiring to the server, switch to the recipe
above.)

---

## 4. WebSocket event

Reuse the existing P2P signaling namespace (where `incomingCall`,
`acceptCall`, etc. live). Add one event:

| Direction | Event | Payload |
| --- | --- | --- |
| Server → client | `call:logged` | `{ entry: <CallLogEntry> }` |

Fired when **the other side** logs an entry. Lets a multi-device user see new
entries without polling. The receiving device should:
1. Upsert by `id` (skip if already in local cache).
2. Render at the top of the list.

The sending side does **not** need this event — they wrote the row, they
already have it.

---

## 5. Database schema (Postgres)

```sql
CREATE TABLE call_log (
  id                TEXT PRIMARY KEY,        -- see §3
  viewer_user_id    UUID NOT NULL,
  peer_user_id      UUID NOT NULL,
  peer_name         TEXT NOT NULL,
  peer_email        TEXT NULL,
  started_at        TIMESTAMPTZ NOT NULL,
  duration_seconds  INT NOT NULL DEFAULT 0,
  direction         TEXT NOT NULL CHECK (direction IN ('outgoing','incoming')),
  outcome           TEXT NOT NULL CHECK (outcome IN ('answered','declined','missed','cancelled','failed')),
  with_video        BOOLEAN NOT NULL DEFAULT TRUE,
  deleted_at        TIMESTAMPTZ NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX call_log_viewer_started
  ON call_log (viewer_user_id, started_at DESC)
  WHERE deleted_at IS NULL;
```

Note: `viewer_user_id` is the user the row belongs to. So a single P2P call
between Alex (caller) and Priya (callee) produces **two rows** — one with
`viewer_user_id = Alex`, `direction = outgoing`; one with `viewer_user_id =
Priya`, `direction = incoming`. This is the simplest schema for "show me my
call log" — no joins, no per-user views.

---

## 6. Rate limits + privacy

- `POST /api/calls/log`: 60 / minute / user (well above the rate of real
  calls; high enough to absorb retries on flaky networks).
- `GET /api/calls/log`: 120 / minute / user.
- `DELETE /api/calls/log`: 5 / hour / user.

Privacy:
- Each row is only ever served to its `viewer_user_id`.
- `peer_email` is included even if the peer's `privacy.allow_chat_discovery`
  is false — you already had the call, so the email is no longer hidden from
  you.
- Retention: configurable via `CALL_LOG_RETENTION_DAYS` env, default 365.

---

## 7. Implementation checklist for the backend dev

- [ ] Migration for the table in §5.
- [ ] REST routes in §2 (Express handlers + JWT middleware + Joi/Zod validators).
- [ ] `call:logged` socket emit on §2.2.
- [ ] Deterministic id helper (§3) — identical recipe in the signaling server
      and the call-log service so both can compute the same id.
- [ ] Soft-delete on `DELETE /log` (don't truncate).
- [ ] Retention job (env-gated; off in dev).
- [ ] OpenAPI export so the iOS/Android/Web clients can codegen.

When the implementation is ready on staging, swap the provider override in
`lib/features/call/call_log_provider.dart`:

```dart
final callLogRepositoryProvider = Provider<CallLogRepository>((ref) {
  // return LocalCallLogRepository();
  return RealCallLogRepository(ApiClient(), p2pSocket);
});
```

The UI (`CallHubScreen` and `_CallLogSection`) doesn't change.

---

## 8. Migration from the local-only v1

Users on the local-only build accumulate entries in SharedPreferences
(`mizdah_p2p_call_log_v1`). When the server ships:

1. On first launch with the new build, the Flutter client reads the local
   blob and POSTs each entry to `/api/calls/log` (idempotent — duplicates are
   harmless because the id collides for entries that the server already had
   from another device).
2. After the upload, the client deletes the local blob and switches to
   server-only reads.

This is a one-shot client-side migration; the backend does nothing special.
