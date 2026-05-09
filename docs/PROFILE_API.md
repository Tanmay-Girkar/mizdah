# Profile API — what's wired and what needs backend confirmation

The Edit profile screen
([lib/features/settings/presentation/edit_profile_screen.dart](../lib/features/settings/presentation/edit_profile_screen.dart))
hits the gateway at `https://192.168.1.100:3001` for three things: name
update, password update, and avatar upload + update. Two of those three are
verified live; the third is a one-line backend check away from working.

This doc exists so the backend dev (a) knows exactly which routes the Flutter
client calls, and (b) confirms the one open question on the avatar flow.

---

## 1. Endpoints used by the Flutter client

All endpoints are at `https://192.168.1.100:3001` on the dev gateway.

### 1.1 Update display name + password

```
POST /api/auth/update
Authorization: Bearer <JWT>
Content-Type: application/json

{
  "name": "New display name"   // optional; sent only if changed
  "password": "new pw"          // optional; sent only when the password
                                //   sheet is submitted
  "avatar_url": "https://..."   // optional; sent after a successful
                                //   /api/files/upload — see §1.3 + §2
}
```

Documented in `MOBILE_API_DOCS.md` §1.4. **Verified** for `name` and
`password` against the dev backend — change persists, `GET /api/auth/me`
returns the new value, and the response body shape matches.

Response (200):
```json
{
  "user": {
    "id": "uuid",
    "email": "...",
    "name": "New display name",
    "role": "USER",
    "avatar_url": "https://..."   // when set
  }
}
```

### 1.2 Get current user

```
GET /api/auth/me
Authorization: Bearer <JWT>
```

Already wired in the auth repository. Returns the user object including
`avatar_url`, which the Flutter `User.fromJson` factory now reads (see
[lib/data/models/models.dart](../lib/data/models/models.dart)).

### 1.3 Upload an image (used for the avatar)

```
POST /api/files/upload
Authorization: Bearer <JWT>
Content-Type: multipart/form-data

field name: "file"   → the image bytes
```

Documented in `MOBILE_API_DOCS.md` §8.1. Response shape:

```json
{
  "id": "file-uuid",
  "fileUrl": "https://.../path/to/file.jpg",
  "fileName": "avatar.jpg",
  "fileSize": 102400,
  "mimeType": "image/jpeg"
}
```

The Flutter client picks an image with `file_picker` (see
[edit_profile_screen.dart `_pickAndUploadAvatar`](../lib/features/settings/presentation/edit_profile_screen.dart)),
POSTs it here, takes the returned `fileUrl`, and immediately calls §1.1 with
`{"avatar_url": "<that fileUrl>"}`.

---

## 2. Open question for the backend dev

**Does `POST /api/auth/update` accept `avatar_url`?**

The signup response on the dev backend already includes `avatar_url` on the
user object (verified live 2026-05-09 — the field exists, it's just `null`
for new users), so the column is there and read-side support is wired. But
nothing in the existing API doc states whether `/api/auth/update` *writes*
that column when an `avatar_url` field is in the request body.

Three possible states on the backend right now:

| Backend behaviour | What you'll see |
| --- | --- |
| ✅ `avatar_url` in the body **is** persisted | Avatar update works end-to-end |
| ⚠️ `avatar_url` in the body is **silently ignored** | Upload succeeds, but `/auth/me` still returns `null` next time |
| ❌ `avatar_url` rejected with 400 | Profile update fails outright |

The Flutter client is defensive — name/password fields are still sent in the
same call, so even if `avatar_url` is silently dropped, the rest of the patch
still goes through. But the user won't see their photo come back on the next
login.

**Action for the backend dev:** confirm (or add) `avatar_url` to the
allow-list of fields on the update handler, so the column gets written from
the same request. Quick sanity test:

```bash
TOKEN="<bearer token>"

# 1. Set avatar_url
curl -sk -X POST https://192.168.1.100:3001/api/auth/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"avatar_url":"https://example.com/me.jpg"}' | jq

# 2. Verify it persisted
curl -sk https://192.168.1.100:3001/api/auth/me \
  -H "Authorization: Bearer $TOKEN" | jq '.user.avatar_url'
# expect: "https://example.com/me.jpg"
```

If the second curl returns the URL, the backend is good — the Flutter
client will work as-is. If it returns `null`, add `avatar_url` to the
handler's writable-fields list.

---

## 3. Verifying the wiring with curl

The dev server requires email verification before login (`403
EMAIL_NOT_VERIFIED`), so to test profile updates you need the JWT from a
verified account. The Flutter app already has one in secure storage after
sign-in; an easy way to grab it is to add a one-line `print(token)` in
`auth_provider.dart:_initialize` and run the app once.

With a token in hand, all three flows can be exercised end-to-end:

```bash
TOKEN="<bearer token>"

# Display name
curl -sk -X POST https://192.168.1.100:3001/api/auth/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User 4"}'

# Password
curl -sk -X POST https://192.168.1.100:3001/api/auth/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"newpass123"}'

# Avatar (two-step)
curl -sk -X POST https://192.168.1.100:3001/api/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/path/to/me.jpg"
# → grab fileUrl from response, then:
curl -sk -X POST https://192.168.1.100:3001/api/auth/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"avatar_url":"<fileUrl>"}'
```

After each call, the Flutter app's auth state will pick up the change on
the next `GET /api/auth/me` (or immediately if the response includes the
fresh user, which §1.1 does).

---

## 4. Where the Flutter client lives

| Concern | File |
| --- | --- |
| User model + `avatar_url` parsing | [`lib/data/models/models.dart`](../lib/data/models/models.dart) |
| REST calls (`updateProfile`, `uploadFile`) | [`lib/data/repositories/auth_repository.dart`](../lib/data/repositories/auth_repository.dart) |
| State (`AuthNotifier.updateProfile`) | [`lib/features/auth/auth_provider.dart`](../lib/features/auth/auth_provider.dart) |
| Edit-profile UI | [`lib/features/settings/presentation/edit_profile_screen.dart`](../lib/features/settings/presentation/edit_profile_screen.dart) |
| Avatar widget (network image + initial fallback) | [`lib/core/ui/mizdah_design.dart`](../lib/core/ui/mizdah_design.dart) `MizdahAvatar` |

Everything is already passing `user.avatarUrl` through; once the backend
confirms §2 the avatar will render across the app (drawer, header,
settings, chats, call log) without any further Flutter changes.
