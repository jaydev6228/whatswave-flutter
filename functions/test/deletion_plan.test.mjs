import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ALL_COLLECTIONS,
  DELIBERATELY_KEPT,
  buildDeletionPlan,
  coveredCollections,
} from '../deletion_plan.js';

test('every collection the app writes has a deletion decision', () => {
  // The test this file exists for. Add a collection to the app without
  // deciding what erasure does with it and this fails -- which is the only
  // thing standing between a new feature and data no deletion request can
  // reach.
  const covered = coveredCollections(buildDeletionPlan('u1'));
  const undecided = ALL_COLLECTIONS.filter((c) => !covered.has(c));
  assert.deepEqual(
    undecided,
    [],
    `no deletion decision for: ${undecided.join(', ')}. Add it to the plan, ` +
      'or to DELIBERATELY_KEPT with a reason.',
  );
});

test('the plan reaches the encryption keys', () => {
  // Destroying these is what makes the kept messages permanently
  // unreadable, so it is the load-bearing part of the whole deletion.
  const plan = buildDeletionPlan('u1');
  const all = [...plan.documentDeletes, ...plan.subcollectionDeletes].join(' ');
  for (const key of ['signalIdentities', 'signalPreKeys', 'signalBackups']) {
    assert.ok(all.includes(key), `${key} must be destroyed`);
  }
});

test('shared documents are edited, never deleted', () => {
  const plan = buildDeletionPlan('u1');
  const deleted = [...plan.documentDeletes, ...plan.subcollectionDeletes].join(' ');
  // Deleting either of these would destroy other people's data.
  assert.ok(!deleted.includes('chatThreads'));
  assert.ok(!deleted.includes('communities'));
  assert.deepEqual(
    plan.membershipRemovals.map((m) => m.collection).sort(),
    ['chatThreads', 'communities'],
  );
});

test('messages and chat media are kept, with a stated reason', () => {
  assert.ok(DELIBERATELY_KEPT['chatThreads/*/messages']);
  assert.ok(DELIBERATELY_KEPT['storage:chatMedia']);
  for (const reason of Object.values(DELIBERATELY_KEPT)) {
    assert.ok(reason.length > 10, 'a kept collection needs a real reason');
  }
});

test('both sides of a call are found, caller and callee', () => {
  const fields = buildDeletionPlan('u1')
    .queryDeletes.filter((q) => q.collection === 'calls')
    .map((q) => q.field)
    .sort();
  assert.deepEqual(fields, ['calleeUid', 'callerUid']);
});

test('the phone directory entry is found by field, not by id', () => {
  // Its document id is a derived phone match key, so it cannot be addressed
  // by uid -- leaving it behind would keep the number mapped to a dead
  // account and block the number from ever registering again.
  const q = buildDeletionPlan('u1').queryDeletes.find(
    (x) => x.collection === 'phoneDirectory',
  );
  assert.deepEqual(q, { collection: 'phoneDirectory', field: 'uid', op: '==', value: 'u1' });
});

test('view records on other people stories are reached', () => {
  // These live under statusStories/{someoneElse}/views/{uid}, so only a
  // collection-group query finds them.
  assert.deepEqual(buildDeletionPlan('u1').collectionGroupDeletes, [
    { group: 'views', docId: 'u1' },
  ]);
});

test('storage prefixes are scoped to the user', () => {
  assert.deepEqual(buildDeletionPlan('u1').storagePrefixes, ['statusMedia/u1/']);
});

test('an empty or non-string uid is refused rather than deleting nothing silently', () => {
  assert.throws(() => buildDeletionPlan(''), TypeError);
  assert.throws(() => buildDeletionPlan(null), TypeError);
  assert.throws(() => buildDeletionPlan(undefined), TypeError);
});
