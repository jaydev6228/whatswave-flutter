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
3. It reads `calls/{roomName}` and confirms that `uid` is actually a party to
   that call -- the caller, the 1:1 callee, or a member of a group call's
   `participantUids`. If not, it returns 403 and mints nothing.
4. It mints a LiveKit token scoped to `identity: uid`, `room: roomName`, and
   returns it.

A caller can only ever get a token identifying themselves -- there's no way
to request a token for a different `uid`, since the identity always comes
from the verified ID token, never from the request body.

Step 3 is the other half of that, and it is not optional. A verified ID token
proves *who* is asking but says nothing about *which* room they may join, and
room names are the `calls/{callId}` document ids. Without the membership check
any signed-in user who learned or guessed a call id could mint a valid
`roomJoin` grant and walk into a conversation between two other people. The
check fails closed: a missing or unreadable call doc denies the token, and a
denial returns the same 403 whether the call does not exist or simply is not
yours, so the endpoint can't be used to enumerate call ids.

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

Expect `{"token": "eyJ..."}` only for a room the token's own user is a party
to -- `test-room` above will return 403 unless a `calls/test-room` doc exists
naming that uid. A missing/invalid Authorization header should return 401; a
missing or malformed `roomName` should return 400; a well-formed room the user
has nothing to do with should return 403.
