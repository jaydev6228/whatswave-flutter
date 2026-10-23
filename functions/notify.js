// Pure fanout logic, kept free of firebase-functions and the Admin SDK so it
// can be unit tested without an emulator. index.js wires it to the trigger.

/// Messages are end-to-end encrypted, so the server cannot read `text`. What
/// it *can* read is the plaintext envelope metadata the protocol needs
/// anyway: who sent it, when, and to which thread. That is enough for a
/// useful notification and is no more than Firestore already sees.
///
/// This deliberately does not attempt to show message content. Doing that
/// properly means a data-only push plus an iOS Notification Service
/// Extension that decrypts on device -- see README.md.
export function buildNotification({ senderName, isGroup, groupName }) {
  const sender = (senderName || '').trim() || 'Someone';
  if (isGroup) {
    return {
      title: (groupName || '').trim() || 'Group',
      body: `${sender} sent a message`,
    };
  }
  return { title: sender, body: 'Sent you a message' };
}

/// Who should be woken for this message.
///
/// `mutedBy` rather than the thread's `isMuted`: that field is a single
/// shared boolean, so honouring it would let one participant silence
/// everyone else's notifications. See README.md -- the client does not write
/// `mutedBy` yet, so mute currently has no effect on push.
export function recipientsFor({ participantUids, senderUid, mutedBy }) {
  const muted = new Set(mutedBy || []);
  return (participantUids || []).filter(
    (uid) => uid && uid !== senderUid && !muted.has(uid),
  );
}

/// FCM reports per-token outcomes in the same order they were sent. A token
/// that is no longer registered will never work again -- the app was deleted
/// or the token rotated -- so it is deleted rather than retried forever.
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

export function deadTokenOwners(responses, owners) {
  const dead = [];
  responses.forEach((response, i) => {
    if (response.success) return;
    const code = response.error?.code;
    if (DEAD_TOKEN_CODES.has(code)) dead.push(owners[i]);
  });
  return dead;
}
