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

import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';

import { buildDeletionPlan } from './deletion_plan.js';

/// Erases the caller's account.
///
/// Callable rather than an HTTP endpoint so the caller's identity comes from
/// a verified Firebase token rather than anything in the request body: a
/// client can only ever delete itself.
///
/// What survives and why is documented in deletion_plan.js. In short:
/// messages already delivered to other people stay, because deleting them
/// rewrites someone else's history -- and they are unreadable anyway once
/// this destroys the identity keys.
export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in to delete your account.');
  }

  const plan = buildDeletionPlan(uid);
  const bulk = db.bulkWriter();

  // Order matters only at the end: the Auth user goes last, so a failure
  // part-way through leaves an account that can retry rather than orphaned
  // data with no way to sign in and clear it.

  for (const path of plan.subcollectionDeletes) {
    await db.recursiveDelete(db.collection(path), bulk);
  }

  for (const path of plan.documentDeletes) {
    bulk.delete(db.doc(path));
  }

  for (const { collection, field, op, value } of plan.queryDeletes) {
    const snap = await db.collection(collection).where(field, op, value).get();
    for (const doc of snap.docs) bulk.delete(doc.ref);
  }

  for (const { group, docId } of plan.collectionGroupDeletes) {
    const snap = await db.collectionGroup(group).get();
    for (const doc of snap.docs) {
      if (doc.id === docId) bulk.delete(doc.ref);
    }
  }

  // Shared documents: remove the member, keep the document.
  for (const { collection, field, value } of plan.membershipRemovals) {
    const snap = await db
      .collection(collection)
      .where(field, 'array-contains', value)
      .get();
    for (const doc of snap.docs) {
      bulk.update(doc.ref, { [field]: FieldValue.arrayRemove(value) });
    }
  }

  await bulk.close();

  for (const prefix of plan.storagePrefixes) {
    try {
      await getStorage().bucket().deleteFiles({ prefix });
    } catch (error) {
      // A missing prefix is the normal case for a user who never posted a
      // status. Worth logging, never worth failing the deletion over.
      logger.warn('storage prefix not fully removed', { prefix, error: error.message });
    }
  }

  // Proof the request was honoured, holding nothing but the fact of it.
  // Written before the Auth delete so it survives even if that step fails.
  await db.doc(`accountDeletions/${uid}`).set({
    deletedAt: FieldValue.serverTimestamp(),
  });

  await getAuth().deleteUser(uid);

  logger.info('account deleted', { uid });
  return { deleted: true };
});
