import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildNotification, recipientsFor, deadTokenOwners } from '../notify.js';

test('a 1:1 notification is titled with the sender', () => {
  assert.deepEqual(
    buildNotification({ senderName: 'Jaydev', isGroup: false }),
    { title: 'Jaydev', body: 'Sent you a message' },
  );
});

test('a group notification is titled with the group, not the sender', () => {
  assert.deepEqual(
    buildNotification({ senderName: 'Jaydev', isGroup: true, groupName: 'Team' }),
    { title: 'Team', body: 'Jaydev sent a message' },
  );
});

test('no notification ever carries message content', () => {
  // The server cannot read it, and must never appear to try. If someone
  // later passes the ciphertext in, this catches it.
  const n = buildNotification({ senderName: 'Jaydev', isGroup: false });
  assert.equal(Object.values(n).join(' ').includes('Sent you a message'), true);
  assert.equal(JSON.stringify(n).length < 120, true);
});

test('a missing sender name degrades rather than printing undefined', () => {
  assert.equal(buildNotification({ isGroup: false }).title, 'Someone');
  assert.equal(buildNotification({ senderName: '  ', isGroup: false }).title, 'Someone');
  assert.equal(
    buildNotification({ senderName: 'A', isGroup: true, groupName: '' }).title,
    'Group',
  );
});

test('the sender is never notified of their own message', () => {
  assert.deepEqual(
    recipientsFor({ participantUids: ['a', 'b', 'c'], senderUid: 'a' }),
    ['b', 'c'],
  );
});

test('a participant who muted the thread is skipped', () => {
  assert.deepEqual(
    recipientsFor({ participantUids: ['a', 'b', 'c'], senderUid: 'a', mutedBy: ['c'] }),
    ['b'],
  );
});

test('muting is per-user -- one muter does not silence the others', () => {
  // The regression that matters: the thread's shared `isMuted` flag must
  // never be what this consults, or one person muting kills everyone's
  // notifications.
  const r = recipientsFor({
    participantUids: ['a', 'b', 'c', 'd'],
    senderUid: 'a',
    mutedBy: ['b'],
  });
  assert.deepEqual(r, ['c', 'd']);
});

test('a removed participant list notifies nobody', () => {
  assert.deepEqual(recipientsFor({ participantUids: [], senderUid: 'a' }), []);
  assert.deepEqual(recipientsFor({ senderUid: 'a' }), []);
});

test('unregistered tokens are collected for deletion', () => {
  const responses = [
    { success: true },
    { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    { success: false, error: { code: 'messaging/internal-error' } },
  ];
  // Only the permanently dead one. A transient internal error must NOT cost
  // the user their token.
  assert.deepEqual(deadTokenOwners(responses, ['a', 'b', 'c']), ['b']);
});

test('a successful send deletes nothing', () => {
  assert.deepEqual(
    deadTokenOwners([{ success: true }, { success: true }], ['a', 'b']),
    [],
  );
});
