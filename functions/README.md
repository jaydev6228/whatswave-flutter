# WhatsWave Cloud Functions

Server-side fanout. Plain JS, no build step, to match `server/livekit-token`.

```bash
npm install
npm test                      # pure logic, no emulator needed
firebase deploy --only functions
```

## Why there is a server at all

`pushTokens/{uid}` was written from the first day of the Firebase integration
and read by nothing. Without this, a message to a backgrounded user produces
no notification. Clients cannot do this themselves: sending to another user's
token requires the Admin SDK, and putting a service account in the app would
hand every user the keys to the project.

## What the notification can and cannot say

Message text is end-to-end encrypted, so the server cannot read it. The
notification is built from the plaintext envelope metadata the protocol needs
anyway — sender name, thread id, whether the thread is a group.

**To show real message content** you need a data-only push plus an iOS
**Notification Service Extension** that decrypts on device before the
notification is displayed. That means a second Xcode target, a shared
keychain access group so the extension can reach the Signal store, and
bridging the Dart crypto to Swift. It is how Signal and WhatsApp do it, and
it is weeks of work rather than days. Android is easier — a background
isolate can decrypt and post a local notification — but shipping it on one
platform only would be worse than shipping it on neither.

## Mute does not work yet

`recipientsFor` consults a per-user `mutedBy` array, **not** the thread's
`isMuted` field. That field is a single shared boolean (see the comment above
`FirestoreChatRepository`), so honouring it would let one participant silence
everyone else's notifications.

Nothing writes `mutedBy` yet, so **muting a thread currently has no effect on
push**. The fix is to make mute per-participant the way `hiddenFor` already
is: write `mutedBy: arrayUnion(uid)` when muting, `arrayRemove(uid)` when
unmuting, and read membership instead of the boolean. The function needs no
change when that lands.

## Three places that must stay in step

The Android notification channel id appears in:

1. `functions/index.js` — `android.notification.channelId`
2. `android/app/src/main/AndroidManifest.xml` — the
   `default_notification_channel_id` meta-data
3. `MainActivity.kt` — the channel actually created at startup

Android 8+ **silently drops** a notification whose channel does not exist. No
error, no log, nothing in the console. If notifications stop appearing on
Android and nothing looks wrong, check these three first.

## Region

Deployed to `asia-northeast1` because Firestore triggers must run in the
database's own region. Deploying elsewhere fails at deploy time rather than
failing silently, which is the one mercy here.

## Not done

- **Call notifications.** A call still does not ring an unopened app. Doing it
  properly on iOS needs PushKit and CallKit, which is a separate project from
  this one.
- **Account deletion.** It needs the Admin SDK to cascade across `users`,
  `signalIdentities`, `signalPreKeys`, `signalBackups`, `signalKeyDeliveries`,
  `pushTokens`, Storage objects and every thread's `participantUids`. This
  codebase is where that belongs. Apple requires in-app deletion.
