# Chats API — backend specification

Status: **Draft v1** — implement against this contract; the Flutter client is
already wired to it via `lib/features/chats/data/chat_repository.dart` (currently
running against an in-memory mock).

This document is the single source of truth for the wire format. If you change a
field name, status code, or socket event here, update the Flutter and web
clients in the same PR.

---

## 1. Identity model

- Every Mizdah user is identified by their **email** (Google sign-in primary
  identity). Internally the DB uses a `user_id` (UUID) as the foreign key, but
  **the wire format uses `email` for sender and participant fields** so a single
  identifier round-trips between mobile, web, and the calendar invite system.
- All chat endpoints are authenticated. Pass the existing Mizdah JWT
  (`Authorization: Bearer <token>`) — the same token issued by `/api/auth/login`
  / Google sign-in. The server resolves the caller from the token and never
  trusts a `sender_email` field in the request body.

---

## 2. REST endpoints

Base path: `/api/chats` (mount under the existing Express app).

All responses are JSON. All timestamps are ISO 8601 UTC strings. Error responses
follow the existing `{ "error": "...", "message": "..." }` shape used elsewhere
in the app.

### 2.1 List conversations

```
GET /api/chats/conversations
```

Returns the caller's conversations, newest activity first. Used to hydrate the
Chats tab on app start.

Response 200:
```json
{
  "conversations": [
    {
      "id": "conv_8f2a...",
      "participants": ["me@gmail.com", "alex.wong@gmail.com"],
      "title": null,
      "last_message": {
        "id": "msg_a1b2",
        "conversation_id": "conv_8f2a...",
        "sender_email": "alex.wong@gmail.com",
        "body": "Did you push the build?",
        "sent_at": "2026-05-09T12:30:11.000Z",
        "status": "delivered"
      },
      "unread_count": 2,
      "updated_at": "2026-05-09T12:30:11.000Z"
    }
  ]
}
```

### 2.2 Open / create a 1:1 conversation

```
POST /api/chats/conversations
Body: { "peer_email": "alex.wong@gmail.com" }
```

Idempotent. If a 1:1 conversation between the caller and `peer_email` already
exists, return it; otherwise create one. Both participant rows are created on
the server side, so the next `GET /conversations` for either user includes it.

Response 200 / 201: same shape as a single conversation in 2.1.

Errors:
- `404 user_not_found` — `peer_email` is not a registered Mizdah user.
- `400 invalid_email` — body missing or malformed.

### 2.3 Fetch message history (paginated)

```
GET /api/chats/conversations/:id/messages?before=<msg_id>&limit=50
```

Reverse-cursor pagination. Without `before`, returns the most recent `limit`
messages, newest last. Pass the **oldest** message id you currently have as
`before` to load the next older page.

Response 200:
```json
{
  "messages": [
    {
      "id": "msg_a1b2",
      "conversation_id": "conv_8f2a...",
      "sender_email": "alex.wong@gmail.com",
      "body": "Did you push the build?",
      "sent_at": "2026-05-09T12:30:11.000Z",
      "status": "delivered",
      "reply_to_id": null
    }
  ],
  "has_more": true
}
```

`limit` is clamped server-side to `[1, 100]`, default 50.

### 2.4 Send a message

```
POST /api/chats/conversations/:id/messages
Body:
{
  "client_id": "tmp_1715...",
  "body": "Sounds good!",
  "reply_to_id": null
}
```

`client_id` is a UUID/string the client generates so optimistic UI rows can be
de-duped when the WebSocket pushes the server-confirmed copy. The server stores
it (column `client_id`) for ~24h to make retries idempotent.

Response 201:
```json
{
  "message": {
    "id": "msg_a1b2",
    "client_id": "tmp_1715...",
    "conversation_id": "conv_8f2a...",
    "sender_email": "me@gmail.com",
    "body": "Sounds good!",
    "sent_at": "2026-05-09T12:30:11.000Z",
    "status": "sent",
    "reply_to_id": null
  }
}
```

Server also pushes `chat:message` over the WebSocket to all participants
(including the sender's other devices). The client should treat the WebSocket
event as authoritative — the REST 201 is just a fast ack for the sending device.

Errors:
- `404 conversation_not_found` — `:id` doesn't exist or caller isn't a member.
- `400 empty_body` — body is empty / whitespace only.
- `413 message_too_long` — bodies are capped at 4000 chars.

### 2.5 Mark conversation as read

```
POST /api/chats/conversations/:id/read
Body: { "up_to_message_id": "msg_a1b2" }   // optional
```

Sets `unread_count = 0` for the caller. If `up_to_message_id` is given, only
messages at or before it are marked; otherwise everything in the conversation
is marked. Server pushes `chat:read` over the WebSocket so the **sender** sees
the read receipt (blue ticks).

Response 204 (no body).

### 2.6 Search users by email

```
GET /api/chats/users/search?q=<query>&limit=10
```

For the New Chat screen. Match by email prefix or display-name substring,
case-insensitive. Excludes the caller from results.

Response 200:
```json
{
  "users": [
    { "email": "alex.wong@gmail.com", "display_name": "Alex Wong", "avatar_url": null }
  ]
}
```

Privacy: this endpoint should only return users who allow being discovered —
add a `privacy.allow_chat_discovery` flag on the user model, defaulting to
true. If false, the user is omitted unless the caller already has a
conversation with them.

### 2.7 Optional v1.1: archive / delete

Out of scope for v1 — planned shape is `POST /conversations/:id/archive` and
`DELETE /conversations/:id/messages/:msgId` (soft delete, sets `body = null`
and `deleted = true`).

---

## 3. WebSocket protocol

Reuse the existing socket.io server. Add a new namespace `/chats` so chat
traffic doesn't share an event-name space with the meeting signaling
(`/signaling-fresh`).

```
ws(s)://<host>/chats?token=<jwt>
```

JWT may also be sent via `auth` payload, matching how signaling already
authenticates.

### 3.1 Server → client events

| Event           | Payload                                                                                                    | Meaning                                                                 |
| --------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `chat:message`  | `{ message: <Message> }`                                                                                   | New message in any conversation the user is a member of.               |
| `chat:status`   | `{ message_id, conversation_id, status: "delivered" \| "read" }`                                           | Status update for a previously-sent message.                            |
| `chat:read`     | `{ conversation_id, reader_email, up_to_message_id }`                                                      | Peer marked the conversation read; flip ticks to blue for those msgs. |
| `chat:typing`   | `{ conversation_id, sender_email }`                                                                        | Peer is typing. Re-fired ~once per 4 seconds while still typing.        |
| `chat:presence` | `{ email, online: true \| false, last_seen: "2026-05-09T..." }`                                            | Peer presence change; clients use this for "online" / "last seen X".  |

`<Message>` matches the REST shape in §2.3.

### 3.2 Client → server events

| Event           | Payload                                                            | Meaning                                                        |
| --------------- | ------------------------------------------------------------------ | -------------------------------------------------------------- |
| `chat:typing`   | `{ conversation_id }`                                              | Throttle to 1 emit per 3s while user is actively typing.       |
| `chat:focus`    | `{ conversation_id }`                                              | Conversation opened; server treats this as "actively viewing".|
| `chat:blur`     | `{ conversation_id }`                                              | Conversation closed.                                           |

Sending messages is **REST only** (§2.4) — keeps retry / idempotency clean.
Don't add a `chat:send` socket event.

### 3.3 Delivery semantics

- When the server stores a new message:
  1. Persist to DB (`status = sent` for the sender's perspective).
  2. Emit `chat:message` to **all participants' active socket connections**
     (sender included — sender's other devices need it).
  3. For each recipient socket, when the server acks the socket emit, send
     `chat:status delivered` back to the sender.
- When a recipient calls `POST /conversations/:id/read`, server emits
  `chat:read` to the **sender's** sockets. Sender flips ticks to blue.
- If a recipient is offline, no `delivered` is sent until their socket
  reconnects and the server replays missed events (see §5).

---

## 4. Database schema (Postgres)

Two tables. Keep migrations small — no joins-on-joins on the hot path.

```sql
-- One row per conversation.
CREATE TABLE chat_conversations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participants    TEXT[] NOT NULL,             -- emails, length=2 for v1
  title           TEXT NULL,                   -- for future group chats
  last_message_id UUID NULL,                   -- denormalised for list view
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX chat_conversations_participants_gin
  ON chat_conversations USING GIN (participants);
CREATE INDEX chat_conversations_updated_at
  ON chat_conversations (updated_at DESC);

-- One row per message.
CREATE TABLE chat_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  sender_email    TEXT NOT NULL,
  body            TEXT NOT NULL,
  reply_to_id     UUID NULL REFERENCES chat_messages(id) ON DELETE SET NULL,
  client_id       TEXT NULL,                   -- for idempotency on send retry
  sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  delivered_to    TEXT[] NOT NULL DEFAULT '{}',-- emails who got the socket push
  read_by         TEXT[] NOT NULL DEFAULT '{}' -- emails who marked read
);
CREATE INDEX chat_messages_conv_sentat
  ON chat_messages (conversation_id, sent_at DESC);
CREATE UNIQUE INDEX chat_messages_client_id
  ON chat_messages (sender_email, client_id)
  WHERE client_id IS NOT NULL;

-- Per-user unread counter — derived but kept materialised for the list view.
CREATE TABLE chat_membership (
  conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
  user_email      TEXT NOT NULL,
  unread_count    INT NOT NULL DEFAULT 0,
  last_read_id    UUID NULL,
  archived        BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (conversation_id, user_email)
);
```

### Computing `status` on read

The wire format `status` field is computed per-recipient at serialisation time:

- `read` if `read_by` contains the **other** participant's email,
- else `delivered` if `delivered_to` contains them,
- else `sent`.

For the sender of the message, the status reflects the receiving side's state.
For incoming messages on the recipient's device, leave `status: "delivered"` —
the recipient never sees their own ticks.

---

## 5. Reconnect / replay

When a socket connects, the client emits `chat:focus` for any conversation it
has open and the server replays:

1. The latest `last_message` for every conversation (covered by REST hydration
   on app start, but on **reconnect** the server should push a delta:
   `chat:message` for any messages newer than the client's `since` cursor).
2. Status updates (`delivered`/`read`) for the user's own outgoing messages
   that happened while disconnected.

Concretely, support this on connect:

```
emit "chat:resume", { since: "2026-05-09T12:30:00.000Z" }
```

Server replies with one or more `chat:message` and `chat:status` events,
oldest-first. Cap at 200 events per resume; if the client is further behind,
they should fall back to a fresh `GET /conversations`.

---

## 6. Rate limits

- `POST /messages`: 30 / minute / user. 429 with `retry_after_seconds`.
- `POST /conversations` (create): 20 / hour / user.
- `chat:typing` (socket): 1 / 3s server-side debounce per conversation per
  sender — drop excess.
- `users/search`: 60 / minute / user.

---

## 7. Auth + privacy

- All endpoints require a valid Mizdah JWT.
- Caller must be a member of the `:id` conversation for any per-conversation
  endpoint — return `404 conversation_not_found` (not 403; don't reveal
  existence).
- `users/search` respects `privacy.allow_chat_discovery` (§2.6).
- All message bodies stored as plaintext server-side (no E2EE in v1). Add a
  `MESSAGE_RETENTION_DAYS` env var, default 365 — a nightly job hard-deletes
  rows older than that.

---

## 8. Test fixtures the Flutter mock uses

The mock repository in `lib/features/chats/data/chat_repository.dart` seeds the
following so the UI demos cleanly. The backend doesn't need these — they're
just for engineers QA'ing parity:

- 7 conversations, peer emails `alex.wong / priya.sharma / marcus.lee /
  jasmine.patel / nikhil.rao / emma.fischer / liu.wei` at `@gmail.com`.
- Conversation 0 has `unread_count = 2`, conversation 2 has `unread_count = 1`,
  rest are 0.
- Each conversation has a 5-message seed thread alternating between peer and
  self.

When the real backend is wired in, point the test fixtures at a seed script
that produces the same shape so QA can switch impls without retraining their
eye.

---

## 9. Implementation checklist for the backend dev

- [ ] Migrations for the three tables in §4.
- [ ] REST routes in §2 (Express handlers, JWT middleware, validation with the
      same lib used elsewhere — Joi/Zod).
- [ ] Socket.io `/chats` namespace with the events in §3.
- [ ] Idempotent `POST /messages` keyed on `(sender_email, client_id)`.
- [ ] Resume-on-reconnect support (§5).
- [ ] Rate limits (§6) — reuse existing rate-limit middleware.
- [ ] Privacy flag on the user model + honour it in `users/search`.
- [ ] Nightly retention job (env-gated; off in dev).
- [ ] OpenAPI (or Postman) export so the iOS/Android/Web clients can codegen.

When the implementation is ready on staging, swap
`chatRepositoryProvider` in `lib/features/chats/chats_provider.dart` from
`MockChatRepository` to a `RealChatRepository(ApiClient(), socketClient)` —
no UI files change.
