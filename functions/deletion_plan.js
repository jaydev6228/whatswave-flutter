// What deleting an account touches, as data rather than control flow, so the
// coverage can be asserted in a test instead of reviewed by eye.

/// Every top-level Firestore collection the app writes. Deletion must have a
/// decision for each one -- the test asserts this list and the plan agree, so
/// adding a collection later fails CI until someone decides what deletion
/// does with it. That is the failure this file exists to prevent: a new
/// collection quietly accumulating data that no erasure request can reach.
export const ALL_COLLECTIONS = [
  'callHistory',
  'calls',
  'chatThreads',
  'communities',
  'phoneDirectory',
  'pushTokens',
  'signalBackups',
  'signalIdentities',
  'signalKeyDeliveries',
  'signalPreKeys',
  'statusMusicTracks',
  'statusStories',
  'userProfiles',
];

/// Documents keyed directly by the uid. Deleted outright.
export const OWNED_BY_UID = [
  'userProfiles',
  'pushTokens',
  'signalIdentities',
  'signalBackups',
  'statusStories',
];

/// Owned documents that carry a subcollection. Firestore does not cascade --
/// deleting the parent leaves orphaned children that are invisible in the
/// console and still readable by path, which is exactly the sort of residue
/// an erasure request is meant to remove.
export const OWNED_SUBCOLLECTIONS = [
  { parent: 'signalPreKeys', child: 'keys' },
  { parent: 'signalKeyDeliveries', child: 'inbox' },
  { parent: 'statusStories', child: 'views' },
];

/// Collections searched by a field rather than the document id.
export const OWNED_BY_QUERY = [
  { collection: 'callHistory', field: 'ownerUid', op: '==' },
  { collection: 'phoneDirectory', field: 'uid', op: '==' },
  { collection: 'calls', field: 'callerUid', op: '==' },
  { collection: 'calls', field: 'calleeUid', op: '==' },
];

/// Shared documents the user is merely a member of. Their uid is removed;
/// the document survives because it belongs to other people too.
export const MEMBERSHIP_FIELDS = [
  { collection: 'chatThreads', field: 'participantUids' },
  { collection: 'communities', field: 'memberUids' },
];

/// Deliberately untouched, each for a stated reason. Listed so the choice is
/// visible rather than an omission someone later mistakes for a bug.
export const DELIBERATELY_KEPT = {
  // Deleting a departing member's messages rewrites every other
  // participant's history. WhatsApp and Signal both keep them. The content
  // is unreadable to us regardless: it is end-to-end encrypted and this
  // deletion destroys the keys.
  'chatThreads/*/messages': 'other participants own their copy of the thread',
  // Same reasoning, and the objects live under chatMedia/{threadId}/ rather
  // than under a uid, so they cannot be found by owner anyway.
  'storage:chatMedia': 'attachments other people received',
  // A shared read-only catalog with no user data in it at all.
  statusMusicTracks: 'no user data',
  // The one thing deletion creates rather than removes: {uid, deletedAt} and
  // nothing else. Retained so the request can be proven honoured, which is a
  // recognised basis under GDPR Art 17(3)(b) -- compliance with a legal
  // obligation -- rather than an exception we invented.
  accountDeletions: 'proof the erasure happened; uid and timestamp only',
};

/// Storage prefixes deleted with the account.
export const OWNED_STORAGE_PREFIXES = ['statusMedia/'];

/// Builds the full set of operations for one uid. Returning a plan rather
/// than performing the writes keeps every decision above assertable.
export function buildDeletionPlan(uid) {
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new TypeError('uid must be a non-empty string');
  }
  return {
    uid,
    documentDeletes: OWNED_BY_UID.map((c) => `${c}/${uid}`),
    subcollectionDeletes: OWNED_SUBCOLLECTIONS.map(
      ({ parent, child }) => `${parent}/${uid}/${child}`,
    ),
    queryDeletes: OWNED_BY_QUERY.map(({ collection, field, op }) => ({
      collection,
      field,
      op,
      value: uid,
    })),
    membershipRemovals: MEMBERSHIP_FIELDS.map(({ collection, field }) => ({
      collection,
      field,
      value: uid,
    })),
    storagePrefixes: OWNED_STORAGE_PREFIXES.map((p) => `${p}${uid}/`),
    // Their view records on *other* people's stories, which live under a
    // path keyed by the story owner, not by the viewer.
    collectionGroupDeletes: [{ group: 'views', docId: uid }],
  };
}

/// Which collections the plan actually reaches. The test compares this with
/// ALL_COLLECTIONS so nothing can be added without a decision.
export function coveredCollections(plan) {
  return new Set([
    ...plan.documentDeletes.map((p) => p.split('/')[0]),
    ...plan.subcollectionDeletes.map((p) => p.split('/')[0]),
    ...plan.queryDeletes.map((q) => q.collection),
    ...plan.membershipRemovals.map((m) => m.collection),
    ...Object.keys(DELIBERATELY_KEPT).filter((k) => !k.includes('/') && !k.startsWith('storage:')),
  ]);
}
