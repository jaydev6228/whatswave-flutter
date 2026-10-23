import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildCallNotification, shouldRingFor } from '../notify.js';

test('a voice and a video call read differently', () => {
  assert.deepEqual(buildCallNotification({ callerName: 'Jaydev', type: 'audio' }),
    { title: 'Jaydev', body: 'Incoming voice call' });
  assert.deepEqual(buildCallNotification({ callerName: 'Jaydev', type: 'video' }),
    { title: 'Jaydev', body: 'Incoming video call' });
});

test('a missing caller name degrades rather than printing undefined', () => {
  assert.equal(buildCallNotification({ type: 'audio' }).title, 'Someone');
  assert.equal(buildCallNotification({ callerName: '  ', type: 'audio' }).title, 'Someone');
});

test('only a ringing call wakes a device', () => {
  const base = { callerUid: 'a', calleeUid: 'b' };
  assert.equal(shouldRingFor({ ...base, status: 'ringing' }), true);
  for (const status of ['accepted', 'declined', 'ended', 'active']) {
    assert.equal(shouldRingFor({ ...base, status }), false,
      `${status} is history, not an invitation`);
  }
});

test('the caller is never rung by their own call', () => {
  assert.equal(
    shouldRingFor({ status: 'ringing', callerUid: 'a', calleeUid: 'a' }),
    false,
  );
});

test('a call with no callee rings nobody', () => {
  assert.equal(shouldRingFor({ status: 'ringing', callerUid: 'a' }), false);
  assert.equal(shouldRingFor({ status: 'ringing', callerUid: 'a', calleeUid: '' }), false);
});

test('a malformed document is refused rather than throwing', () => {
  assert.equal(shouldRingFor(null), false);
  assert.equal(shouldRingFor(undefined), false);
  assert.equal(shouldRingFor({}), false);
});
