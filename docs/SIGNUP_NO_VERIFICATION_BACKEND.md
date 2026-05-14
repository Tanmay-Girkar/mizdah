# Signup — Direct-to-Home (No Email Verification Gate)

Companion doc to
[PHONE_AND_CONTACTS_BACKEND.md](./PHONE_AND_CONTACTS_BACKEND.md).
That one specified signup with phone. This one removes the
**email-verification gate** that currently blocks the user from
landing on the Home screen the moment they finish registering.

## The user-facing problem this fixes

Today, after a successful signup the backend returns:

```jsonc
HTTP/1.1 200 OK
{
  "user":  { ...with phone, phone_country, email, etc. },
  "requiresVerification": true,
  "emailSent": true
  // NO token field — and no token in Set-Cookie either
}
```

The Flutter client has no choice but to push the dedicated
`/verify-email` screen ("Check your email") because:

- No token → every subsequent authenticated API call returns 401.
- The existing 401 interceptor in `api_client.dart` clears all
  local state and bounces the user back to `/login`.
- So if the client just navigated to `/` (Home), the user would
  land there for ~1 second, then get force-logged-out the moment
  the Home screen fired its first request.

The product call is to **drop the verification gate at signup**.
Verification can return later as a *soft nudge* (e.g. a
dismissible banner in the app, or a hard requirement only for
sensitive flows like password reset).

Effort: **~30 minutes** of backend work. Zero new tables, zero
schema changes — just one response-shape change on one endpoint.

---

## 0. Conventions

Same as the parent doc:

- Gateway: `https://<dev-host>:3001` (dev),
  `https://mizdah-backend.ogoul.cloud` (prod).
- `Authorization: Bearer <JWT>` for all authenticated routes.
- Bodies: `application/json`.
- Errors: `{ "error": "human readable", "code": "MACHINE_READABLE" }`.

---

## 1. Summary of changes

| Change | Where | Status |
|---|---|---|
| Always return a JWT on successful signup | `POST /api/auth/signup` response | NEW |
| Drop the `requiresVerification`-only success path (the "no token, account created" branch) | same endpoint | NEW |
| Existing `email_verified` column stays on the user — defaults to `false`, can be flipped later via a separate verify flow if you want one | DB | unchanged |
| `POST /api/auth/login` no longer rejects unverified accounts with `403 EMAIL_NOT_VERIFIED` (or keeps doing so — see §4 for the recommended call) | login endpoint | optional revisit |

Nothing else.

---

## 2. Endpoint — `POST /api/auth/signup` (revised response)

### 2.1 Request — unchanged

Same as
[PHONE_AND_CONTACTS_BACKEND.md §2.1](./PHONE_AND_CONTACTS_BACKEND.md):

```jsonc
POST /api/auth/signup
Content-Type: application/json
(no auth — public endpoint)

{
  "name":          "Alice Example",
  "email":         "alice@example.com",
  "password":      "hunter2",
  "phone":         "+919876543210",
  "phone_country": "IN"
}
```

### 2.2 Response — new success shape

```jsonc
HTTP/1.1 201 Created           // or 200 — whichever you already use,
                               // doesn't matter to the client
{
  "user": {
    "id":             "usr_01HX...",
    "email":          "alice@example.com",
    "name":           "Alice Example",
    "phone":          "+919876543210",
    "phone_country":  "IN",
    "avatar_url":     null,
    "role":           "USER",
    "email_verified": false      // kept for the soft-nudge flow
  },
  "token": "<JWT>"               // <-- THIS is what was missing before
}
```

Two things to notice:

1. **`token` is always present** on a successful signup. Issue it
   the same way you issue the token on `POST /api/auth/login`. Use
   the same signing key + expiration window. From this moment the
   user is fully authenticated against every other endpoint.
2. **`requiresVerification` and `emailSent` are removed** from the
   response shape. The client doesn't need to know about
   verification state on signup any more — the only thing it does
   with that information today is push the "Check your email"
   screen, which we're getting rid of.

### 2.3 Token in the body OR `Set-Cookie`

The existing client code already handles both:

```dart
// auth_repository.dart:
if (data['token'] == null) {
  data['token'] = _extractTokenFromHeaders(response.headers);
}
```

Whichever transport you prefer is fine. The body form is simpler
to reason about; the cookie form matches the existing
`POST /api/auth/login` flow. Match login for consistency.

### 2.4 Error responses — unchanged

All current 4xx codes from
[PHONE_AND_CONTACTS_BACKEND.md §2.4](./PHONE_AND_CONTACTS_BACKEND.md)
stay as-is:

| HTTP | `code` | When |
|---|---|---|
| 400 | `INVALID_PHONE` | bad / missing phone |
| 400 | `INVALID_PHONE_COUNTRY` | missing / mismatched country |
| 409 | `PHONE_ALREADY_TAKEN` | phone owned by another account |
| 409 | `EMAIL_ALREADY_TAKEN` | email owned by another account |
| 400 | `WEAK_PASSWORD` | password rules failed |

Validation order also unchanged — validate phone before writing
anything, etc.

---

## 3. Soft-nudge for verification (optional, recommended)

Verification doesn't go away, it just stops blocking. Two cheap
hooks worth keeping:

### 3.1 Keep `users.email_verified` column

Already exists per the live response (the field showed up in our
curl probe). Default `false` on new signups. Flip to `true` when
the user taps the link in the verification email.

The Flutter side can show a dismissible banner like
"Verify your email" on the Home screen when
`user.email_verified == false`. Optional, deferable.

### 3.2 Keep sending the verification email on signup

Same flow as today — backend dispatches the verification email
the moment the account is created. The link still works. The
only thing that changes is: the user can use the app **before**
clicking the link.

If the user never clicks the link, that's fine — the
`email_verified` flag stays `false` forever, and you can decide
later whether to gate any specific feature on it (e.g.
"can't reset password until you verify").

---

## 4. Tied-in change — `POST /api/auth/login` should accept unverified accounts

Currently, login an unverified account returns:

```jsonc
HTTP/1.1 403 Forbidden
{ "error": "Email not verified", "code": "EMAIL_NOT_VERIFIED" }
```

After this change, signup creates an authenticated session
immediately, so a fresh signup doesn't *need* to log in again.
But the legacy 2M users + anyone who eventually re-installs the
app will hit `/api/auth/login` with an unverified email.

**Recommended:** drop the 403 EMAIL_NOT_VERIFIED check on login.
Let unverified users log in normally. Keep the
`email_verified` flag for the soft nudge.

If you want to keep the check for some accounts (e.g. enterprise
SSO-linked accounts, paid plans, whatever), make it opt-in per
account or per plan — but the default for consumer accounts
should be "no gate".

The Flutter side already handles the 403 case (shows "Verify your
email first..."), so dropping the check on the backend just
changes the path the user lands on after login from a friendly
error to a successful Home-screen load. No client change required.

---

## 5. End-to-end test cases

### 5.1 Signup returns a token

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{
    "name":"Test User",
    "email":"newuser+5_1@example.com",
    "password":"hunter22",
    "phone":"+918313868999",
    "phone_country":"IN"
  }'

# Expect: 201 (or 200) with a `token` field in the body OR an
#         `auth_token=...` cookie in Set-Cookie.
#         `requiresVerification` should NOT be present in the body
#         (or if present, must be `false`).
```

### 5.2 The returned token works against `/api/auth/me`

```bash
# Grab token from §5.1 (either body or cookie) and reuse:
curl -k https://192.168.1.20:3001/api/auth/me \
  -H "Authorization: Bearer $TOKEN"

# Expect: 200, response.user contains the same id/email/phone
#         from §5.1. Crucially: NOT 401 EMAIL_NOT_VERIFIED.
```

### 5.3 Login with the just-created account (unverified) succeeds

```bash
curl -k -X POST https://192.168.1.20:3001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"newuser+5_1@example.com","password":"hunter22"}'

# Expect: 200, response.user.email_verified == false, token returned.
# NOT 403 EMAIL_NOT_VERIFIED.
```

### 5.4 Existing user flows still work (regression)

```bash
# Re-run §5.1 with the SAME email → expect 409 EMAIL_ALREADY_TAKEN.
# Re-run §5.1 with the SAME phone → expect 409 PHONE_ALREADY_TAKEN.
# Run §5.1 with phone == "123" → expect 400 INVALID_PHONE.
```

### 5.5 Verification email link still works

After §5.1, the user receives the verification email. Tapping the
link should still flip `users.email_verified` to `true`. Confirm
via:

```bash
curl -k https://192.168.1.20:3001/api/auth/me \
  -H "Authorization: Bearer $TOKEN"

# Expect: response.user.email_verified == true once the link is
#         tapped. The token from §5.1 remains valid throughout.
```

---

## 6. Roll-out order

Trivially small. No staged rollout needed.

1. **Update signup handler** — always issue a JWT, drop the
   `requiresVerification` short-circuit branch.
2. **Drop `EMAIL_NOT_VERIFIED` block from login** (or make it
   opt-in).
3. **Run the test cases in §5.**
4. **Ship.**

Backend can ship this independently of the Flutter side. The
Flutter client already handles both the "token present" and
"token absent" success paths — once the backend always returns a
token, the existing `if (token == null)` branch in
`auth_provider.dart` becomes dead code and can be removed in a
later cleanup (no urgency).

---

## 7. Security note — what changes

This loosens one anti-spam control: a bot could mass-register
accounts without going through "tap the verification link". The
existing rate limit on `POST /api/auth/signup` (per IP / per
device) becomes the primary anti-bot protection.

If you want stronger anti-spam **without** putting verification
back in the critical path:

- Rate-limit signup per IP (e.g. 5/hour per IP).
- Apply a CAPTCHA on signup attempts above a threshold.
- Apply the verified-email requirement only on *destructive* or
  *paid* actions later (password reset, plan upgrade, transferring
  ownership, etc.) — not on consumer-app sign-in.

This is the same model WhatsApp / Telegram use: signup is
frictionless; trust is layered on for high-risk operations.

Out of scope for this doc — just listed so the security review
isn't surprised.

---

## 8. What the Flutter side does once this ships

**Nothing needs to change.** The existing code path in
[`lib/features/auth/auth_provider.dart`](../lib/features/auth/auth_provider.dart):

```dart
if (token == null) {
  // verification-required branch — currently routes to /verify-email
}
final token = data['token'];   // <-- this becomes the only path
final user = User.fromJson(...);
await StorageService.saveToken(token);
state = state.copyWith(
  status: AuthStatus.authenticated, token: token, user: user);
```

…already sets the authenticated state when a token is present. The
register screen's `ref.listen<AuthState>` already routes to `/`
the moment status flips to `authenticated`.

So **the moment the backend starts returning a token on signup,
the "Check your email" screen disappears on its own and users land
directly on Home.** Zero Flutter changes required.

The `/verify-email` screen itself can stay in the codebase — it's
small, harmless when never invoked, and we can wire it to a manual
"Resend verification email" flow later if you want a settings
toggle for that.

---

## TL;DR for the backend dev

| Task | Effort |
|---|---|
| §2 Return JWT on signup (drop the `requiresVerification` no-token branch) | 15 min |
| §4 Stop rejecting unverified accounts on login (recommended bundle) | 10 min |
| §5 Test cases automated | 15 min |
| **Total** | **~40 minutes** |

Questions / clarifications → ping the Flutter dev. Once shipped,
the "Check your email" screen disappears on its own — no Flutter
release needed.
