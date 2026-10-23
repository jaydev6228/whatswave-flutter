import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { logger } from 'firebase-functions';

import { buildNotification, recipientsFor, deadTokenOwners } from './notify.js';

initializeApp();

// Firestore triggers must run in the database's own region. This project's
// (default) database is in asia-northeast1; deploying elsewhere fails at
// deploy time with a region mismatch rather than silently not firing.
setGlobalOptions({ region: 'asia-northeast1', maxInstances: 10 });

const db = getFirestore();

export const notifyOnMessage = onDocumentCreated(
  'chatThreads/{threadId}/messages/{messageId}',
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const { threadId, messageId } = event.params;
    const senderUid = message.senderUid;
    if (!senderUid) return;

    // A delete-for-everyone tombstone is written as an update, not a create,
    // so it never reaches here -- but a message created already-deleted
    // would, and is not worth waking anyone for.
    if (message.isDeleted === true) return;

    const threadSnap = await db.doc(`chatThreads/${threadId}`).get();
    if (!threadSnap.exists) {
      logger.warn('message in a thread that does not exist', { threadId });
      return;
    }
    const thread = threadSnap.data();

    const recipients = recipientsFor({
      participantUids: thread.participantUids,
      senderUid,
      mutedBy: thread.mutedBy,
    });
    if (recipients.length === 0) return;

    // One read per recipient. Fine at this scale; a thread with thousands of
    // members would want the tokens denormalised onto the thread instead.
    const tokenSnaps = await db.getAll(
      ...recipients.map((uid) => db.doc(`pushTokens/${uid}`)),
    );

    const tokens = [];
    const owners = [];
    for (const snap of tokenSnaps) {
      const token = snap.data()?.token;
      if (typeof token === 'string' && token.length > 0) {
        tokens.push(token);
        owners.push(snap.id);
      }
    }
    if (tokens.length === 0) return;

    const { title, body } = buildNotification({
      senderName: message.senderName,
      isGroup: thread.isGroup === true,
      groupName: thread.groupName,
    });

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      // The client reads these to open the right thread when the
      // notification is tapped.
      data: { threadId, messageId, type: 'message' },
      android: {
        priority: 'high',
        notification: { channelId: 'messages', tag: threadId },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            // Collapses older notifications from the same chat rather than
            // stacking one per message.
            'thread-id': threadId,
          },
        },
      },
    });

    const dead = deadTokenOwners(response.responses, owners);
    if (dead.length > 0) {
      const batch = db.batch();
      for (const uid of dead) batch.delete(db.doc(`pushTokens/${uid}`));
      await batch.commit();
      logger.info('removed unregistered push tokens', { count: dead.length });
    }

    if (response.failureCount > 0) {
      logger.warn('some pushes failed', {
        threadId,
        sent: response.successCount,
        failed: response.failureCount,
      });
    }
  },
);
