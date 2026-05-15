# File-service: `uploaderId` should come from the JWT, not the form body

**Owner:** file-service / gateway team
**Status:** mobile workaround shipped; backend fix still pending
**Endpoint:** `POST /api/files/upload`
**File on backend:** `backend/file-service/src/controllers/fileController.js` (around line 50)

## What's broken

Every profile-photo upload from the mobile app returns **HTTP 500** with this body:

```json
{"error":"\nInvalid `prisma.fileMetadata.create()` invocation in\n/Users/ashish/Desktop/mizdah/backend/file-service/src/controllers/fileController.js:50:52\n\n  47     fileUrl = `${base}/${encodeURIComponent(filename)}`;\n  48 }\n  49 \n→ 50 const metadata = await prisma.fileMetadata.create({\n       data: {\n         meetingId: undefined,\n         fileUrl: \"/api/file/uploads/1778834048137-lavender-field-sunset-near-valensole_268835-3910.jpg\",\n         fileType: \"image/jpeg\",\n         size: 102484,\n     +   uploaderId: String\n       }\n     })\n\nArgument `uploaderId` is missing."}
```

`prisma.fileMetadata.create({ data })` requires `uploaderId: String` but the
controller never sets it.

## Why the mobile client can't fix this cleanly

Every request from the app already includes:

```
Authorization: Bearer <JWT>
```

The auth middleware on the gateway decodes that JWT and (for every other
endpoint) attaches `req.user = { id, email, ... }`. The file-service
controller should pull `req.user.id` and use it as `uploaderId`. Asking
the mobile client to also re-send the user id as a form field is wrong
on two counts:

1. **Trust** — the form-body value is whatever the client puts there.
   Any logged-in user could upload a file and tag it as another user.
   `uploaderId` MUST come from the verified JWT, not the form.
2. **Redundancy** — the server already knows who's calling. Asking the
   client to repeat itself is just an extra failure mode.

## The fix (backend)

In `fileController.js` around line 50, derive `uploaderId` from
`req.user.id` instead of letting it be `undefined`:

```js
// before
const metadata = await prisma.fileMetadata.create({
  data: {
    meetingId,
    fileUrl,
    fileType,
    size,
    // uploaderId implicitly undefined — Prisma rejects
  },
});

// after
const uploaderId = req.user?.id;
if (!uploaderId) {
  return res.status(401).json({ error: 'AUTH_REQUIRED' });
}
const metadata = await prisma.fileMetadata.create({
  data: {
    meetingId,
    fileUrl,
    fileType,
    size,
    uploaderId,
  },
});
```

Make sure the auth middleware actually runs **before** the multer/multipart
handler on this route. If the route order in the file-service Express app
is `multer → controller` with no JWT verifier in between, add the same
`requireAuth` middleware the rest of the API uses:

```js
// in the router
router.post(
  '/upload',
  requireAuth,                 // ← THIS — populates req.user
  upload.single('file'),       // multer
  fileController.upload,       // your handler
);
```

## Temporary mobile workaround (already shipped)

Until the backend lands the fix above, the mobile app sends `uploaderId`
as an explicit form field next to `file`:

```
POST /api/files/upload
Content-Type: multipart/form-data; boundary=...

--...
Content-Disposition: form-data; name="file"; filename="photo.jpg"
Content-Type: image/jpeg

<bytes>
--...
Content-Disposition: form-data; name="uploaderId"

<the current user's id>
--...
```

When the backend fix lands, the mobile workaround can stay (harmless —
backend just ignores the body field and uses JWT) until the next mobile
release, at which point the `uploaderId` param on
`AuthRepository.uploadFile()` can be removed.

## How to test the fix

```bash
# 1. log in to get a JWT
TOKEN=$(curl -k -s -X POST https://192.168.1.20:3001/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"<pw>"}' \
  | jq -r .token)

# 2. upload without a uploaderId form field — should now 200, not 500
curl -k -s -X POST https://192.168.1.20:3001/api/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/path/to/test.jpg" \
  | jq

# expected:
# { "fileUrl": "/api/file/uploads/...-test.jpg", ... }
```
