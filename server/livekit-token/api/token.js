const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { AccessToken } = require('livekit-server-sdk');

// Room names are caller-supplied; keep them to a safe, predictable shape
// (call IDs / UIDs) so they can't be used to inject unexpected grant scope.
const ROOM_NAME_PATTERN = /^[a-zA-Z0-9_-]{1,128}$/;

function getFirebaseApp() {
  const apps = getApps();
  if (apps.length) {
    return apps[0];
  }

  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!encoded) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not configured.');
  }

  const serviceAccount = JSON.parse(
    Buffer.from(encoded, 'base64').toString('utf8'),
  );

  return initializeApp({
    credential: cert(serviceAccount),
  });
}

/**
 * Is `uid` actually a party to the call whose room this is?
 *
 * A verified ID token only proves *who* the caller is -- on its own it says
 * nothing about *which* room they may join. Without this check any signed-in
 * user who learned or guessed a call id could mint a `roomJoin` grant for a
 * conversation they have nothing to do with.
 *
 * `roomName` is always the id of the call's own Firestore doc, for both call
 * shapes (see FirestoreCallSignalingService.placeCall / placeGroupCall, which
 * set `roomName: docRef.id` and `roomName: hostRef.id`), so one read answers
 * it:
 *
 *   1:1    calls/{roomName} -> { callerUid, calleeUid }
 *   group  calls/{roomName} -> { callerUid, isGroup: true, participantUids }
 *
 * Group invitees each get their own ringing doc at `{roomName}_{inviteeUid}`,
 * but every one of them carries the same bare `roomName` field and the client
 * only ever sends that -- so the host doc, which lists every invitee in
 * `participantUids`, is the one doc worth reading.
 *
 * Fails closed: an unreadable or missing call doc denies the token.
 */
async function isCallParticipant(app, roomName, uid) {
  const snapshot = await getFirestore(app)
    .collection('calls')
    .doc(roomName)
    .get();

  if (!snapshot.exists) {
    return false;
  }

  const call = snapshot.data() || {};

  if (call.callerUid === uid || call.calleeUid === uid) {
    return true;
  }

  return (
    call.isGroup === true &&
    Array.isArray(call.participantUids) &&
    call.participantUids.includes(uid)
  );
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ')
    ? authHeader.slice('Bearer '.length)
    : null;

  if (!idToken) {
    res.status(401).json({ error: 'Missing Authorization: Bearer <idToken> header' });
    return;
  }

  const roomName = req.body?.roomName;
  if (typeof roomName !== 'string' || !ROOM_NAME_PATTERN.test(roomName)) {
    res.status(400).json({ error: 'roomName must match ' + ROOM_NAME_PATTERN });
    return;
  }

  // Initialising the Admin SDK and verifying a token are separate failures
  // and must not share a catch. A missing or malformed
  // FIREBASE_SERVICE_ACCOUNT_JSON is a server misconfiguration, and
  // reporting it as 401 "invalid token" sends every operator hunting the
  // client instead of the deployment -- which is exactly what happened
  // after a key rotation left the variable unset.
  let app;
  try {
    app = getFirebaseApp();
  } catch (error) {
    console.error('Firebase Admin initialisation failed:', error);
    res.status(500).json({ error: 'Auth backend is not configured' });
    return;
  }

  let uid;
  try {
    const decoded = await getAuth(app).verifyIdToken(idToken);
    uid = decoded.uid;
  } catch (error) {
    console.error('ID token verification failed:', error);
    res.status(401).json({ error: 'Invalid or expired Firebase ID token' });
    return;
  }

  try {
    if (!(await isCallParticipant(app, roomName, uid))) {
      // Deliberately the same response whether the call doc is missing or
      // simply isn't theirs -- distinguishing the two would turn this
      // endpoint into an oracle for which call ids exist.
      console.warn('Denied token: uid is not a party to this call');
      res.status(403).json({ error: 'Not a participant in that call' });
      return;
    }
  } catch (error) {
    console.error('Call membership lookup failed:', error);
    res.status(500).json({ error: 'Could not verify call membership' });
    return;
  }

  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  if (!apiKey || !apiSecret) {
    res.status(500).json({ error: 'LIVEKIT_API_KEY / LIVEKIT_API_SECRET are not configured' });
    return;
  }

  const at = new AccessToken(apiKey, apiSecret, {
    identity: uid,
    ttl: '10m',
  });
  at.addGrant({ room: roomName, roomJoin: true });

  const token = await at.toJwt();
  res.status(200).json({ token });
};
