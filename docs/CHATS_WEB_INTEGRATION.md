# Chats — web integration flow

How to integrate the chat feature into the Mizdah **web** client (whatever
framework — React/Next.js, Vue, Svelte, or plain TS). This document is
prescriptive: follow the steps end-to-end and you will end up with a working
1:1 chat that matches the Flutter app feature-for-feature.

The wire format is fully specified in [CHATS_API.md](CHATS_API.md). Read that
first.

---

## Contents

1. Architecture
2. Auth (Google sign-in → Mizdah JWT)
3. App startup: REST hydration + socket connect
4. Chats list screen
5. Chat detail screen (the thread)
6. Sending: optimistic UI + idempotency
7. Receiving: socket → store → UI
8. Read receipts + typing
9. Reconnect strategy
10. Offline queue
11. Notifications
12. Tests + parity with the Flutter app

---

## 1. Architecture

Three layers, mirroring the Flutter app:

```
 ┌──────────────────────────────────────────────────────────────┐
 │ UI components (ChatsList, ChatDetail, NewChat, MessageBubble) │
 └──────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┴─────────────────┐
              │   chatStore (Zustand / Pinia /   │
              │   Redux Toolkit / Vuex — pick)   │
              └────────────────┬─────────────────┘
                               │
                ┌──────────────┴──────────────┐
                │       chatClient.ts         │
                │ ┌─────────────────────────┐ │
                │ │  REST  (fetch / axios)  │ │
                │ ├─────────────────────────┤ │
                │ │  Socket.io client       │ │
                │ └─────────────────────────┘ │
                └─────────────────────────────┘
```

- **`chatClient.ts`** — owns one `axios` instance (or `fetch` wrapper) and one
  `socket.io-client` connection. Exposes typed methods that map 1:1 to the
  REST routes in §2 of the API doc and exposes the socket events as a typed
  `EventEmitter`.
- **`chatStore`** — single source of truth for `conversations`, `messages`,
  `typingByConversation`, `presenceByEmail`, and `connectionState`. Selectors
  read from this; UI components never reach into `chatClient` directly.
- **UI** — dumb. Reads selectors, dispatches store actions on user input.

Why this split: when the backend changes a field, you change `chatClient.ts`
once. When you redesign the UI, you don't touch the store. This is the same
pattern as `lib/features/chats/data/chat_repository.dart` +
`lib/features/chats/chats_provider.dart` in the Flutter app.

### Recommended dependencies

- `socket.io-client@^4`
- `axios` or native `fetch`
- `zustand` (recommended for React) or your existing store
- `dayjs` or `date-fns` for time formatting (mirror the rules in §4 below)
- `nanoid` for `client_id` generation

---

## 2. Auth

The chat backend uses the same JWT as the rest of Mizdah. Web users sign in
with Google → backend returns a JWT → store it in `localStorage` (or a
`httpOnly` cookie if you switch to that pattern). **Use the existing flow** —
do not invent a chat-specific auth.

```ts
// Persist on login
localStorage.setItem('mizdah_token', token);
localStorage.setItem('mizdah_email', user.email);
```

Both the REST client and the socket client must attach this token:

```ts
// chatClient.ts
const token = () => localStorage.getItem('mizdah_token') ?? '';
const email = () => localStorage.getItem('mizdah_email') ?? '';

const http = axios.create({
  baseURL: '/api/chats',
  headers: { 'Content-Type': 'application/json' },
});
http.interceptors.request.use(cfg => {
  cfg.headers.Authorization = `Bearer ${token()}`;
  return cfg;
});

import { io } from 'socket.io-client';
const socket = io('/chats', {
  autoConnect: false,
  auth: () => ({ token: token() }),
  transports: ['websocket'],
});
```

If the JWT expires, the server emits `connect_error: jwt_expired` — refresh
through the existing refresh-token endpoint, then `socket.connect()` again.

---

## 3. App startup

Two parallel tasks on app boot, after auth resolves:

```ts
async function bootChats() {
  // (a) hydrate the conversation list (cheap, non-blocking for the UI shell)
  const { conversations } = await http.get('/conversations').then(r => r.data);
  store.setConversations(conversations);

  // (b) open the socket and start receiving deltas
  socket.connect();
  socket.on('connect', () => {
    const since = store.getLastEventAt(); // localStorage; null on first run
    socket.emit('chat:resume', { since });
  });
}
```

Run `bootChats()` once on app load. Keep the socket connected for the lifetime
of the tab.

---

## 4. Chats list screen

UI layout — match the Flutter app:

- Avatar (initials, palette-coloured by hashing the email)
- Display name on top, last message preview below
- Time (right-aligned, top): today → `h:mm a`; yesterday → `Yesterday`;
  this week → weekday name; older → `MMM d`
- Unread count badge if `unread_count > 0`
- Search bar above the list — filters locally on `name` + `email` + last
  message body (no extra round trip)
- A floating "+" button → opens the New Chat modal/screen

State binding:

```ts
const conversations = useChatStore(s =>
  s.conversations.toSorted((a, b) =>
    new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
  )
);
```

When the user clicks a row → navigate to `/chats/:id` and **immediately**
`store.markConversationLocallyRead(id)` so the badge clears without waiting
for the network. Then call `POST /conversations/:id/read` in the background.

---

## 5. Chat detail screen

Layout (top → bottom):

1. Top bar — back button, peer avatar, peer name, presence dot, video/audio
   call buttons.
2. Bubble list — outgoing right-aligned (gradient bg, white text), incoming
   left-aligned (surface bg, ink text). Group consecutive bubbles from the
   same sender within a 5-minute window — only the **last** bubble in a group
   shows the tail and the time.
3. Composer — emoji button, expanding textarea (1–6 lines), attachment
   button (placeholder), send button.

Hydration:

```ts
useEffect(() => {
  // 1. fetch initial history (newest 50)
  const { messages } = await http
    .get(`/conversations/${id}/messages`)
    .then(r => r.data);
  store.setThread(id, messages);

  // 2. tell the server we're focused — drives presence + read receipts
  socket.emit('chat:focus', { conversation_id: id });
  socket.emit('chat:read', { conversation_id: id });

  return () => socket.emit('chat:blur', { conversation_id: id });
}, [id]);
```

Pagination on scroll-up:

```ts
async function loadOlder() {
  const oldest = thread[0]?.id;
  if (!oldest) return;
  const { messages, has_more } = await http
    .get(`/conversations/${id}/messages`, { params: { before: oldest } })
    .then(r => r.data);
  store.prependThread(id, messages);
  store.setHasMore(id, has_more);
}
```

---

## 6. Sending: optimistic UI + idempotency

The send flow has four steps. They MUST happen in this order so retries don't
duplicate messages.

```ts
async function send(conversationId: string, body: string) {
  // 1. Generate a stable client_id — survives retries.
  const client_id = nanoid();
  const optimistic = {
    id: `tmp_${client_id}`,
    client_id,
    conversation_id: conversationId,
    sender_email: email(),
    body,
    sent_at: new Date().toISOString(),
    status: 'sending' as const,
  };

  // 2. Append to the store immediately — UI shows the bubble with a clock
  //    tick.
  store.appendMessage(conversationId, optimistic);

  try {
    // 3. POST /messages with the same client_id. The server uses
    //    (sender_email, client_id) as a unique key — duplicates on retry are
    //    rejected and the original row is returned.
    const { message } = await http
      .post(`/conversations/${conversationId}/messages`, {
        client_id, body, reply_to_id: null,
      })
      .then(r => r.data);

    // 4. Replace the optimistic row by id match (tmp_<client_id> → server id)
    //    OR by client_id field if the server echoes it.
    store.replaceMessage(conversationId, optimistic.id, message);
  } catch (err) {
    store.markFailed(conversationId, optimistic.id);
  }
}
```

If the user retries a failed bubble, **reuse the same `client_id`** — that's
how idempotency works. Don't generate a new one.

---

## 7. Receiving: socket → store → UI

One handler set, registered once during `bootChats()`:

```ts
socket.on('chat:message', ({ message }) => {
  // Dedup by client_id when the sender's own server-confirmed echo lands.
  store.upsertMessage(message);
  if (message.sender_email !== email()) {
    store.bumpUnread(message.conversation_id);
    // browser notification — see §11
  }
  store.setLastEventAt(message.sent_at);
});

socket.on('chat:status', ({ message_id, conversation_id, status }) => {
  store.updateStatus(conversation_id, message_id, status);
});

socket.on('chat:read', ({ conversation_id, reader_email, up_to_message_id }) => {
  store.markReadUpTo(conversation_id, up_to_message_id, reader_email);
});

socket.on('chat:typing', ({ conversation_id, sender_email }) => {
  store.setTyping(conversation_id, sender_email);
  // auto-clear after 5s — see store implementation hint below
});

socket.on('chat:presence', p => store.setPresence(p.email, p));
```

`store.upsertMessage` is the most important method. Its job: if a message with
the same `client_id` is already in the thread (the optimistic row), **replace**
it. Otherwise, append. This is what de-dupes the sender's own echo.

---

## 8. Read receipts + typing

Reads are driven from the **viewer**:

- When a conversation is open and a new message arrives, after the bubble
  enters the viewport, send `socket.emit('chat:read', { conversation_id })`.
- The server records it and emits `chat:read` to the **other participant**'s
  sockets. They flip ticks to blue.

Typing — debounce so you don't hammer the socket:

```ts
const sendTyping = throttle(
  (conversationId: string) =>
    socket.emit('chat:typing', { conversation_id: conversationId }),
  3000,
  { leading: true, trailing: false }
);
// onChange:
function onComposerInput(v: string) {
  setText(v);
  if (v.trim()) sendTyping(conversationId);
}
```

Display — fade out the typing hint after 5s if no fresh ping arrives:

```ts
// store
setTyping(conversationId, email) {
  this.typingByConversation[conversationId] = {
    email, expiresAt: Date.now() + 5000,
  };
  setTimeout(() => {
    const t = this.typingByConversation[conversationId];
    if (t && t.email === email && t.expiresAt <= Date.now()) {
      delete this.typingByConversation[conversationId];
      this.notify();
    }
  }, 5100);
}
```

---

## 9. Reconnect strategy

`socket.io-client` reconnects automatically. Listen for the lifecycle:

```ts
socket.on('disconnect', () => store.setConnectionState('disconnected'));
socket.on('reconnect_attempt', () => store.setConnectionState('connecting'));
socket.on('connect', () => {
  store.setConnectionState('connected');
  socket.emit('chat:resume', { since: store.getLastEventAt() });
});
```

`store.getLastEventAt()` is the `sent_at` of the most recent event you
processed — persist it to `localStorage` so reload + reconnect both work.

If `chat:resume` returns more than 200 events, the server caps it. In that
case, fall back to a fresh `GET /conversations` and accept the gap — the user
sees an up-to-date list, just no animation of catch-up messages.

---

## 10. Offline queue

If the user types and hits send while offline:

1. Append the optimistic bubble with `status: 'sending'` exactly like §6.
2. Don't call REST yet — push the `{conversationId, client_id, body}` onto a
   `pendingSends` queue in localStorage.
3. When the socket reconnects (`store.connectionState === 'connected'`), flush
   the queue: for each item, call `POST /messages` with the same `client_id`.

Idempotency on the server (§6) means flushing twice is harmless — the duplicate
returns the original row.

---

## 11. Notifications

Browser notifications for incoming messages when the conversation isn't open:

```ts
socket.on('chat:message', ({ message }) => {
  store.upsertMessage(message);
  if (
    message.sender_email !== email() &&
    document.visibilityState === 'hidden' &&
    Notification.permission === 'granted'
  ) {
    new Notification(message.sender_email.split('@')[0], {
      body: message.body,
      tag: message.conversation_id, // collapses repeated notifications
    });
  }
});
```

Ask permission lazily — the first time the user has a conversation open and
sends/receives. Don't prompt on app load.

---

## 12. Tests + parity with the Flutter app

The Flutter mock repository
([chat_repository.dart](../lib/features/chats/data/chat_repository.dart))
seeds 7 conversations. Make your dev backend seed the same 7 (same emails,
same names, same `unread_count` distribution, same body strings) so QA can
flip between the two apps and visually compare. Any divergence → file a bug
against whichever side drifted.

Recommended automated tests:

- **Unit:** `chatClient.send` — mocks `axios` + the socket; verifies the
  optimistic → ack → echo flow leaves exactly one bubble in the thread.
- **Unit:** `store.upsertMessage` — verifies dedup by `client_id`.
- **Integration:** open two browser tabs as different users against staging,
  send a message, assert: optimistic in A → real id in A → bubble in B → read
  receipt back in A within 5s.

When you wire the same flow into the Flutter `RealChatRepository`, both
clients share the contract → bugs surface as protocol-level issues, not
client-specific quirks.

---

## Summary — minimum viable web client checklist

- [ ] `chatClient.ts` with REST + socket helpers, both auth'd with the JWT.
- [ ] `chatStore` with `conversations`, threads keyed by id, typing,
      presence, connection state, last-event cursor.
- [ ] Routes: `/chats`, `/chats/new`, `/chats/:id`.
- [ ] Optimistic send with `client_id`.
- [ ] Socket handlers for `message`, `status`, `read`, `typing`, `presence`.
- [ ] Read-on-focus + typing throttle.
- [ ] Reconnect with `chat:resume`.
- [ ] LocalStorage queue for offline sends.
- [ ] Browser notifications.

Ship in that order — every step is independently demoable.
