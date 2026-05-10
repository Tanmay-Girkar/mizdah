# Push notifications — backend specification

Status: **Draft v1** — implement against this contract; the Flutter
client is already wired (FCM init, token retrieval, tap routing,
post-login registration). This doc is the contract the backend
needs to honour.

---

## 1. Setup (one-time)

The Firebase project (`mizdah-ce042`) is already provisioned:

- **Android app** — `com.mizdah.mizdah` — `android/app/google-services.json` is committed.
- **iOS app** — bundle id under `ios/Runner/GoogleService-Info.plist`.
- **Web** — keys live in `lib/firebase_options.dart` (auto-generated).

What the backend dev needs:

1. Download the Firebase **Admin SDK service account key** from the Firebase Console:
   - Console → Project settings → Service accounts → Generate new private key
   - Save as `mizdah-firebase-admin.json` somewhere the backend can read.
2. Set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/mizdah-firebase-admin.json` in your service env.
3. Install the FCM Admin SDK (Node example):
   ```bash
   npm install firebase-admin
   ```

That's the entire backend setup. The Admin SDK uses the service account to mint per-request access tokens — no API keys to rotate.

---

## 2. REST endpoints to implement

### 2.1 Register a device token

```
POST /api/notifications/devices
Authorization: Bearer <user JWT>
Content-Type: application/json

{
  "token": "fLk8pX...long FCM token",
  "platform": "android"   // or "iOS" or "web"
}
```

Persist a row in a `device_tokens` table keyed on `(user_id, token)`. If the same token already exists for this user, return 200 with the existing row (idempotent). If the token exists for a *different* user, **transfer** it — the user just signed in on a device that previously belonged to someone else.

Suggested schema:

```sql
CREATE TABLE device_tokens (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  platform   TEXT NOT NULL CHECK (platform IN ('android','iOS','web')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (token)
);
CREATE INDEX device_tokens_user ON device_tokens (user_id);
```

`token` is the primary key (FCM tokens are globally unique). The `user_id` is a foreign key but **not** part of the PK so token transfers are a single UPDATE.

Response 200 / 201:
```json
{ "status": "registered" }
```

### 2.2 Unregister a device token

```
DELETE /api/notifications/devices/<token>
Authorization: Bearer <user JWT>
```

Hard-delete the row. Called from the Flutter client on logout. Backend must verify the caller's `user_id` matches the row's `user_id` before deleting (so user A can't unregister user B's device).

Response 204 (no content).

### 2.3 List my devices (optional, v2)

```
GET /api/notifications/devices
Authorization: Bearer <user JWT>
```

Returns the array of devices currently registered for the caller. Useful for a future "devices" management screen in Settings.

---

## 3. Sending a notification — the JSON shape

The Flutter client routes taps based on the `data.type` field. It expects **one of four types**, each with type-specific fields plus `title` / `body` for the visible notification text.

The wire format goes through the FCM Admin SDK:

```js
const admin = require('firebase-admin');
await admin.messaging().send({
  token: deviceToken,        // or `tokens: [...]` for multicast
  notification: { title, body },
  data: {
    // String values only — FCM rejects non-string data fields.
    type: '<chat|call|meeting|schedule>',
    ...typeSpecificFields,
  },
  android: {
    priority: 'high',        // wakes the device for calls
    notification: {
      channelId: 'mizdah_general_v1',
      sound: 'default',
    },
  },
  apns: {
    payload: {
      aps: {
        sound: 'default',
        contentAvailable: true,
      },
    },
  },
});
```

### 3.1 New chat message — `type=chat`

Sent to the recipient when their peer sends a message and the recipient is offline / app backgrounded.

```js
{
  notification: {
    title: 'Alex Wong',                    // peer display name
    body: 'Hey, are you free for a call?', // message body
  },
  data: {
    type: 'chat',
    conversation_id: 'conv_8f2a...',
    sender_email: 'alex@gmail.com',
    sender_user_id: 'uuid...',             // optional
    message_id: 'msg_a1b2',                // optional, for analytics
  },
}
```

**Tap behaviour:** the Flutter client opens `/chats/<conversation_id>` so the recipient lands directly on the thread.

**When to send:** server-side, immediately after the message row is persisted in the chat-messages table. Look up the recipient's `device_tokens`; if they have one or more, send to all (multicast). If the recipient is currently online (active socket on the `/chats` namespace) **don't** send — the in-app delivery is enough.

### 3.2 Incoming P2P call — `type=call`

```js
{
  notification: {
    title: 'Incoming call',
    body: 'Alex Wong is calling',
  },
  data: {
    type: 'call',
    caller_user_id: 'uuid...',
    caller_name: 'Alex Wong',
    caller_email: 'alex@gmail.com',
    call_id: 'call_abc',
    with_video: 'true',                     // string!
  },
}
```

**Tap behaviour:** opens `/p2p-call`. The actual ringing UI is handled by the existing `P2PIncomingOverlay` — the push is a wake-up so the device notification plays even when the app is fully backgrounded / killed.

**Special:** Android requires `priority: 'high'` and APNs requires `aps.contentAvailable: true` so the device wakes the radio. iOS additionally needs **VoIP push (PushKit)** for true Skype/WhatsApp-style ringing on a locked screen — that's a v2 enhancement. For v1, regular high-priority FCM works for "you have an incoming call" banners while the app is backgrounded but still installed.

### 3.3 Meeting invite / reminder — `type=meeting`

```js
{
  notification: {
    title: 'Meeting starting soon',
    body: 'Mizdah Meeting · 2:00 PM',
  },
  data: {
    type: 'meeting',
    meeting_code: 'abcdefghij',
    meeting_id: 'uuid...',          // optional
    starts_at: '2026-05-09T14:00:00.000Z',
  },
}
```

**Tap behaviour:** opens `/pre-join/<meeting_code>` so the user lands on the join screen with the code already filled in.

### 3.4 Schedule changed — `type=schedule`

```js
{
  notification: {
    title: 'Meeting moved',
    body: 'Quarterly review is now on Tuesday at 4 PM',
  },
  data: {
    type: 'schedule',
    schedule_id: 'uuid...',
  },
}
```

**Tap behaviour:** opens `/meetings?tab=upcoming`.

---

## 4. Targeting a user across devices

A single user can have multiple device tokens (phone + web + tablet). Send to **all** of them:

```js
const tokens = await db('device_tokens').where({ user_id: recipientId }).pluck('token');
if (tokens.length === 0) return;
await admin.messaging().sendEachForMulticast({
  tokens,
  notification: { ... },
  data: { ... },
});
```

The Admin SDK's `sendEachForMulticast` returns a per-token result — invalid tokens come back with `error.code === 'messaging/registration-token-not-registered'`. **Delete those rows from `device_tokens` immediately** — the user uninstalled the app or the token rotated and the new one will register on next launch.

```js
const result = await admin.messaging().sendEachForMulticast({ tokens, ... });
const stale = [];
result.responses.forEach((r, i) => {
  if (!r.success && r.error?.code === 'messaging/registration-token-not-registered') {
    stale.push(tokens[i]);
  }
});
if (stale.length) await db('device_tokens').whereIn('token', stale).delete();
```

---

## 5. Don't push when the user is online

For chats specifically, **don't send a push when the recipient already has an active `/chats` socket**. Their app is open and the in-app delivery is instant; a duplicate push notification is annoying.

Suggested check:

```js
const isOnline = chatSocketServer.userIsConnected(recipientId);
if (!isOnline) {
  await sendPush(recipientId, payload);
}
```

Same heuristic for P2P calls — if the recipient's signaling socket is connected, the existing `incomingCall` socket event already drives the ringing UI; the push is redundant and causes a double-buzz.

For meeting reminders / schedule changes, **always** push regardless of online status — those are time-sensitive and the user might not be looking at the app even when "online."

---

## 6. Foreground vs background — what FCM does for you

| App state          | Notification displayed?                | Data delivered to client? |
| ------------------ | -------------------------------------- | ------------------------- |
| Foreground         | **No** — your client must show its own banner / snackbar | Yes — `onMessage` fires   |
| Background         | **Yes** — OS shows the system notif    | Yes — when user taps      |
| Terminated         | **Yes** — OS shows the system notif    | Yes — when user taps; client gets it via `getInitialMessage` |

The Flutter client handles all three:
- Foreground → `PushNotificationService.foregroundMessages` stream → UI listens and shows in-app banner.
- Background tap → `taps` stream → routes via `_handleTap` in `lib/main.dart`.
- Cold-start tap → `taps` stream (replayed via `getInitialMessage`).

So the **backend just sends one payload shape**; the OS + client decide presentation.

---

## 7. Verification recipe (curl)

End-to-end smoke test once the endpoints are wired:

```bash
TOKEN="<user JWT>"
BASE="https://192.168.1.100:3001"

# 1. Register a fake device token (the Flutter client does this
#    automatically; this is just for backend testing).
curl -sk -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -X POST $BASE/api/notifications/devices \
  -d '{"token":"fake_curl_token_123","platform":"android"}'

# 2. List devices for this user.
curl -sk -H "Authorization: Bearer $TOKEN" $BASE/api/notifications/devices

# 3. Trigger a chat message and check the FCM Admin SDK logs.
#    (No specific endpoint — just send a chat msg to a user whose
#    socket isn't connected.)

# 4. Unregister.
curl -sk -H "Authorization: Bearer $TOKEN" \
  -X DELETE $BASE/api/notifications/devices/fake_curl_token_123
```

Real-device testing: pull a real token off the device's debug log
(the Flutter client prints `[push] token=<first 16 chars>…` on
startup). Use the **full** token for a one-shot test:

```bash
node -e '
const admin = require("firebase-admin");
admin.initializeApp({ credential: admin.credential.applicationDefault() });
admin.messaging().send({
  token: "<full 152-char token from device log>",
  notification: { title: "Hello", body: "Test from curl" },
  data: { type: "chat", conversation_id: "test_conv" },
}).then(console.log).catch(console.error);
'
```

If the device shows the notification within 1–2 seconds, the entire pipeline works end-to-end.

---

## 8. Implementation checklist

- [ ] Migration for `device_tokens` table (§2.1).
- [ ] `POST /api/notifications/devices` route (idempotent, with token-transfer logic).
- [ ] `DELETE /api/notifications/devices/<token>` with caller-ownership check.
- [ ] Firebase Admin SDK initialized at service start with the service account JSON.
- [ ] Helper `sendPush(userId, payload)` that:
  - Looks up all tokens for `userId`
  - Calls `admin.messaging().sendEachForMulticast`
  - Deletes any tokens that come back as `registration-token-not-registered`
- [ ] Hook `sendPush('chat', recipientId, ...)` into the chat-message-create flow, gated on "recipient is offline."
- [ ] Hook `sendPush('call', calleeId, ...)` into the P2P `initiateCall` socket handler, gated on "callee socket not connected."
- [ ] (v2) Hook `sendPush('meeting', invitedUserId, ...)` into the schedule-create flow.
- [ ] OpenAPI export so the iOS / web clients can codegen.

When all of the above is live, the Flutter client receives notifications without any further changes — the wiring is already done.
