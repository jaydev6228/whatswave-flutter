const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
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

  let uid;
  try {
    const app = getFirebaseApp();
    const decoded = await getAuth(app).verifyIdToken(idToken);
    uid = decoded.uid;
  } catch (error) {
    console.error('ID token verification failed:', error);
    res.status(401).json({ error: 'Invalid or expired Firebase ID token' });
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
