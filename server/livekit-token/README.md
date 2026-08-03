# WhatsWave LiveKit token server

A single Vercel serverless function (`api/token.js`) that mints per-user
LiveKit access tokens. Exists so real calling doesn't need a Firebase Cloud
Function (which requires the Blaze billing plan) -- this deploys to Vercel's
free tier instead.

## How it works

1. The Flutter app sends `POST /api/token` with `{ "roomName": "..." }` and
   an `Authorization: Bearer <firebase-id-token>` header.
2. The function verifies that ID token against this Firebase project (via
   `firebase-admin`, using the service account key below) to get the
   caller's real `uid`.
3. It mints a LiveKit token scoped to `identity: uid`, `room: roomName`, and
   returns it.

A caller can only ever get a token identifying themselves -- there's no way
to request a token for a different `uid`, since the identity always comes
from the verified ID token, never from the request body.

## Environment variables (set in the Vercel dashboard, never committed)

| Variable | Where to get it |
|---|---|
| `LIVEKIT_API_KEY` | LiveKit Cloud project settings |
| `LIVEKIT_API_SECRET` | LiveKit Cloud project settings |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase Console -> Project settings -> Service accounts -> Generate new private key, then base64-encode the downloaded file: `base64 -i serviceAccountKey.json \| pbcopy` (macOS) |

For local testing with `vercel dev`, copy `.env.example` to `.env` and fill
in the same three values (`.env` is gitignored).

## Deploy

```bash
npm install -g vercel
vercel login
cd server/livekit-token
vercel link
vercel env add LIVEKIT_API_KEY
vercel env add LIVEKIT_API_SECRET
vercel env add FIREBASE_SERVICE_ACCOUNT_JSON
vercel --prod
```

## Test

```bash
curl -X POST https://<your-deployment>.vercel.app/api/token \
  -H "Authorization: Bearer <a real Firebase ID token>" \
  -H "Content-Type: application/json" \
  -d '{"roomName": "test-room"}'
```

Expect `{"token": "eyJ..."}`. A missing/invalid Authorization header should
return 401; a missing `roomName` should return 400.
