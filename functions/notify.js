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

/// An incoming call, as a notification.
///
/// Calls reach the callee through a Firestore snapshot listener, which the OS
/// suspends the moment the app is backgrounded -- so without a push the call
/// never arrives at all and the caller just waits. This is the push.
export function buildCallNotification({ callerName, type }) {
  const caller = (callerName || '').trim() || 'Someone';
  const isVideo = type === 'video';
  return {
    title: caller,
    body: isVideo ? 'Incoming video call' : 'Incoming voice call',
  };
}

/// Whether a freshly created call document should ring anyone.
///
/// A call is written once per invitee, so group calls arrive here as several
/// documents. Only a ringing call with a callee is worth waking a device for;
/// anything already accepted, declined or ended is history being written, not
/// an invitation.
export function shouldRingFor(call) {
  if (!call) return false;
  if (call.status !== 'ringing') return false;
  if (typeof call.calleeUid !== 'string' || call.calleeUid.length === 0) {
    return false;
  }
  // Never ring the person who placed it.
  return call.calleeUid !== call.callerUid;
}
