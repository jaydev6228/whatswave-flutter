// Security-rules tests for firestore.rules.
//
// These rules ARE the app's authorization boundary: who may read a thread,
// which single field a group admin may change, whose key you may touch in a
// reactions map. None of that is enforced in Dart -- a modified client talks
// to Firestore directly -- so the rules are the only thing standing between
// one user's data and another's, and they were previously covered by nothing.
//
// Run with: npm run test:rules

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, '..', '..');

const ALICE = 'alice'; // group admin
const BOB = 'bob'; // ordinary member
const CAROL = 'carol'; // ordinary member
const DAVE = 'dave'; // not in any thread

let testEnv;

/** Seeds documents with rules bypassed, the way a server would. */
const seed = (fn) => testEnv.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const anonymous = () => testEnv.unauthenticatedContext().firestore();

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-whatswave',
    firestore: {
      rules: readFileSync(join(projectRoot, 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    // A group: alice is the only admin.
    await setDoc(doc(db, 'chatThreads/g1'), {
      participantUids: [ALICE, BOB, CAROL],
      groupAdminUids: [ALICE],
      isGroup: true,
      groupName: 'Design Sprint',
      groupDescription: 'Motion and rollout',
      unreadCounts: { [ALICE]: 0, [BOB]: 0, [CAROL]: 0 },
    });
    await setDoc(doc(db, 'chatThreads/g1/messages/m1'), {
      senderUid: BOB,
      senderName: 'Bob',
      text: 'original text',
      attachments: [],
      deliveryState: 'delivered',
    });

    // A community announcements channel: members read, only admins post.
    await setDoc(doc(db, 'chatThreads/ann1'), {
      participantUids: [ALICE, BOB],
      groupAdminUids: [ALICE],
      isGroup: true,
      isAnnouncementOnly: true,
      groupName: 'Announcements',
    });

    // A 1:1 thread, using the deterministic sorted-uid id the repository
    // builds -- the story read rule reconstructs this exact id.
    await setDoc(doc(db, `chatThreads/${ALICE}_${BOB}`), {
      participantUids: [ALICE, BOB],
      isGroup: false,
    });
  });
});

describe('chatThreads: read access', () => {
  it('lets a participant read their thread', async () => {
    await assertSucceeds(getDoc(doc(as(BOB), 'chatThreads/g1')));
  });

  it('denies a signed-in non-participant', async () => {
    await assertFails(getDoc(doc(as(DAVE), 'chatThreads/g1')));
  });

  it('denies an unauthenticated reader', async () => {
    await assertFails(getDoc(doc(anonymous(), 'chatThreads/g1')));
  });

  it('allows reading a thread that does not exist yet', async () => {
    // Deliberate: startThread() probes the deterministic id before creating
    // it. A missing doc exposes nothing either way.
    await assertSucceeds(getDoc(doc(as(DAVE), 'chatThreads/does-not-exist')));
  });

  it('denies creating a thread the creator is not a participant of', async () => {
    await assertFails(
      setDoc(doc(as(DAVE), 'chatThreads/forged'), {
        participantUids: [ALICE, BOB],
        isGroup: false,
      }),
    );
  });

  it('never allows deleting a thread, even by an admin', async () => {
    await assertFails(deleteDoc(doc(as(ALICE), 'chatThreads/g1')));
  });
});

describe('chatThreads: group management is admin-only', () => {
  it('lets an admin rename the group', async () => {
    await assertSucceeds(
      updateDoc(doc(as(ALICE), 'chatThreads/g1'), { groupName: 'Renamed' }),
    );
  });

  it('denies a non-admin member renaming the group', async () => {
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1'), { groupName: 'Hijacked' }),
    );
  });

  it('denies a non-admin editing the description', async () => {
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1'), { groupDescription: 'nope' }),
    );
  });

  it('denies a non-admin promoting themselves to admin', async () => {
    // The whole privilege-escalation path in one assertion.
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1'), {
        groupAdminUids: [ALICE, BOB],
      }),
    );
  });

  it('denies a non-admin adding themselves to another thread', async () => {
    await assertFails(
      updateDoc(doc(as(DAVE), `chatThreads/${ALICE}_${BOB}`), {
        participantUids: [ALICE, BOB, DAVE],
      }),
    );
  });

  it('lets a member change their own thread state (mute/pin/archive)', async () => {
    await assertSucceeds(
      updateDoc(doc(as(BOB), 'chatThreads/g1'), { isMuted: true }),
    );
  });

  it('denies smuggling a group rename alongside an allowed field', async () => {
    // The permissive member-state rule is gated on an affectedKeys()
    // exclusion list; this is the test that the exclusion actually holds.
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1'), {
        isMuted: true,
        groupName: 'Hijacked',
      }),
    );
  });
});

describe('messages: read and create', () => {
  it('lets a participant read messages', async () => {
    await assertSucceeds(getDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1')));
  });

  it('denies a non-participant reading messages', async () => {
    await assertFails(getDoc(doc(as(DAVE), 'chatThreads/g1/messages/m1')));
  });

  it('denies a non-participant listing messages', async () => {
    await assertFails(getDocs(collection(as(DAVE), 'chatThreads/g1/messages')));
  });

  it('lets a participant send as themselves', async () => {
    await assertSucceeds(
      setDoc(doc(as(BOB), 'chatThreads/g1/messages/new1'), {
        senderUid: BOB,
        senderName: 'Bob',
        text: 'hello',
        attachments: [],
      }),
    );
  });

  it('denies sending a message forged as someone else', async () => {
    await assertFails(
      setDoc(doc(as(BOB), 'chatThreads/g1/messages/forged'), {
        senderUid: CAROL,
        senderName: 'Carol',
        text: 'Carol did not write this',
        attachments: [],
      }),
    );
  });

  it('denies a non-participant sending into the thread', async () => {
    await assertFails(
      setDoc(doc(as(DAVE), 'chatThreads/g1/messages/intruder'), {
        senderUid: DAVE,
        senderName: 'Dave',
        text: 'let me in',
        attachments: [],
      }),
    );
  });

  it('never allows deleting a message document', async () => {
    await assertFails(deleteDoc(doc(as(BOB), 'chatThreads/g1/messages/m1')));
  });
});

describe('messages: announcement-only threads', () => {
  it('lets an admin post an announcement', async () => {
    await assertSucceeds(
      setDoc(doc(as(ALICE), 'chatThreads/ann1/messages/a1'), {
        senderUid: ALICE,
        senderName: 'Alice',
        text: 'Heads up',
        attachments: [],
      }),
    );
  });

  it('denies an ordinary member posting an announcement', async () => {
    await assertFails(
      setDoc(doc(as(BOB), 'chatThreads/ann1/messages/a2'), {
        senderUid: BOB,
        senderName: 'Bob',
        text: 'can I post here',
        attachments: [],
      }),
    );
  });
});

describe('messages: per-user field ownership', () => {
  it('lets a participant add their own reaction', async () => {
    await assertSucceeds(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        reactions: { [CAROL]: '👍' },
      }),
    );
  });

  it("denies writing another user's reaction", async () => {
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        reactions: { [BOB]: '👎' },
      }),
    );
  });

  it('lets a participant star a message for themselves', async () => {
    await assertSucceeds(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        starredBy: [CAROL],
      }),
    );
  });

  it("denies starring on another user's behalf", async () => {
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        starredBy: [BOB],
      }),
    );
  });

  it('denies leaking a message to an outsider by starring it for them', async () => {
    // This is why the rule above matters rather than being cosmetic.
    // `match /{path=**}/messages/{messageId}` grants read to anyone listed
    // in starredBy, so if a participant can put an arbitrary uid there they
    // can hand a non-participant read access to that message.
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        starredBy: [DAVE],
      }),
    );
    // And the outsider must still not be able to read it.
    await assertFails(getDoc(doc(as(DAVE), 'chatThreads/g1/messages/m1')));
  });

  it('lets a participant unstar only themselves', async () => {
    await seed((db) =>
      updateDoc(doc(db, 'chatThreads/g1/messages/m1'), {
        starredBy: [BOB, CAROL],
      }),
    );
    // Removing own uid: fine.
    await assertSucceeds(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        starredBy: [BOB],
      }),
    );
  });

  it("denies unstarring on another user's behalf", async () => {
    await seed((db) =>
      updateDoc(doc(db, 'chatThreads/g1/messages/m1'), {
        starredBy: [BOB, CAROL],
      }),
    );
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        starredBy: [CAROL],
      }),
    );
  });

  it('lets a participant hide a message for themselves only', async () => {
    await assertSucceeds(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        hiddenFor: [CAROL],
      }),
    );
  });

  it('denies hiding a message for everyone else', async () => {
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        hiddenFor: [BOB, CAROL],
      }),
    );
  });
});

describe('messages: edit and delete-for-everyone are sender-only', () => {
  it('lets the sender edit their own message', async () => {
    await assertSucceeds(
      updateDoc(doc(as(BOB), 'chatThreads/g1/messages/m1'), {
        text: 'edited',
        isEdited: true,
      }),
    );
  });

  it('denies another participant editing it', async () => {
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        text: 'put words in Bob mouth',
        isEdited: true,
      }),
    );
  });

  it('denies an edit that does not set isEdited', async () => {
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1/messages/m1'), {
        text: 'silently changed',
      }),
    );
  });

  it('lets the sender delete for everyone when content is cleared', async () => {
    await assertSucceeds(
      updateDoc(doc(as(BOB), 'chatThreads/g1/messages/m1'), {
        text: '',
        attachments: [],
        isDeleted: true,
      }),
    );
  });

  it('denies a delete-for-everyone that leaves the text behind', async () => {
    await assertFails(
      updateDoc(doc(as(BOB), 'chatThreads/g1/messages/m1'), {
        text: 'still here',
        attachments: [],
        isDeleted: true,
      }),
    );
  });

  it('denies a non-sender deleting for everyone', async () => {
    await assertFails(
      updateDoc(doc(as(CAROL), 'chatThreads/g1/messages/m1'), {
        text: '',
        attachments: [],
        isDeleted: true,
      }),
    );
  });
});

describe('statusStories', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, `statusStories/${ALICE}`), {
        name: 'Alice',
        previewText: 'On the beach',
        segments: [],
      });
    });
  });

  it('lets the owner read their own story', async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), `statusStories/${ALICE}`)));
  });

  it('lets someone who has chatted with the owner read it', async () => {
    // bob shares the alice_bob thread seeded above.
    await assertSucceeds(getDoc(doc(as(BOB), `statusStories/${ALICE}`)));
  });

  it('denies a stranger with no shared chat', async () => {
    await assertFails(getDoc(doc(as(DAVE), `statusStories/${ALICE}`)));
  });

  it("denies writing someone else's story", async () => {
    await assertFails(
      setDoc(doc(as(BOB), `statusStories/${ALICE}`), { previewText: 'forged' }),
    );
  });

  it('lets a viewer record their own view progress', async () => {
    await assertSucceeds(
      setDoc(doc(as(BOB), `statusStories/${ALICE}/views/${BOB}`), {
        seenSegments: 1,
      }),
    );
  });

  it("denies writing another viewer's progress", async () => {
    await assertFails(
      setDoc(doc(as(BOB), `statusStories/${ALICE}/views/${CAROL}`), {
        seenSegments: 99,
      }),
    );
  });
});

describe('signal key distribution', () => {
  it('lets anyone signed in read an identity so they can start a chat', async () => {
    await seed((db) =>
      setDoc(doc(db, `signalIdentities/${ALICE}`), { registrationId: 1 }),
    );
    // dave shares no thread with alice and still must be able to fetch her
    // public keys -- otherwise nobody could ever message her first.
    await assertSucceeds(getDoc(doc(as(DAVE), `signalIdentities/${ALICE}`)));
  });

  it("denies overwriting someone else's identity key", async () => {
    // The impersonation path: if this were allowed, an attacker could
    // substitute their own key for alice's and read messages meant for her
    // from anyone who had not verified her safety number.
    await seed((db) =>
      setDoc(doc(db, `signalIdentities/${ALICE}`), { registrationId: 1 }),
    );
    await assertFails(
      setDoc(doc(as(DAVE), `signalIdentities/${ALICE}`), { registrationId: 9 }),
    );
  });

  it('lets the owner publish their own identity', async () => {
    await assertSucceeds(
      setDoc(doc(as(ALICE), `signalIdentities/${ALICE}`), {
        registrationId: 7,
      }),
    );
  });

  it('lets another user consume a one-time pre-key', async () => {
    // Deleting someone else's pre-key is the protocol: a one-time key is
    // used once, by the person who fetches it.
    await seed((db) =>
      setDoc(doc(db, `signalPreKeys/${ALICE}/keys/1`), { id: 1, publicKey: 'k' }),
    );
    await assertSucceeds(getDoc(doc(as(BOB), `signalPreKeys/${ALICE}/keys/1`)));
    await assertSucceeds(
      deleteDoc(doc(as(BOB), `signalPreKeys/${ALICE}/keys/1`)),
    );
  });

  it("denies publishing pre-keys into someone else's pool", async () => {
    // Forged pre-keys would let an attacker hand out keys they hold the
    // private half of, under alice's name.
    await assertFails(
      setDoc(doc(as(DAVE), `signalPreKeys/${ALICE}/keys/2`), {
        id: 2,
        publicKey: 'forged',
      }),
    );
  });

  it('lets the owner publish their own pre-keys', async () => {
    await assertSucceeds(
      setDoc(doc(as(ALICE), `signalPreKeys/${ALICE}/keys/3`), {
        id: 3,
        publicKey: 'k',
      }),
    );
  });

  it('lets a member post a sender key into another member inbox', async () => {
    await assertSucceeds(
      setDoc(doc(as(ALICE), `signalKeyDeliveries/${BOB}/inbox/d1`), {
        senderUid: ALICE,
        threadId: 'g1',
        type: 'senderKeyDistribution',
        payload: 'sealed',
        createdAt: 1,
      }),
    );
  });

  it('denies forging a delivery as somebody else', async () => {
    await assertFails(
      setDoc(doc(as(DAVE), `signalKeyDeliveries/${BOB}/inbox/d2`), {
        senderUid: ALICE,
        threadId: 'g1',
        type: 'senderKeyDistribution',
        payload: 'forged',
        createdAt: 1,
      }),
    );
  });

  it('lets only the recipient read and consume their inbox', async () => {
    await seed((db) =>
      setDoc(doc(db, `signalKeyDeliveries/${BOB}/inbox/d3`), {
        senderUid: ALICE,
        threadId: 'g1',
        type: 'senderKeyDistribution',
        payload: 'sealed',
        createdAt: 1,
      }),
    );
    await assertFails(
      getDoc(doc(as(ALICE), `signalKeyDeliveries/${BOB}/inbox/d3`)),
    );
    await assertSucceeds(
      getDoc(doc(as(BOB), `signalKeyDeliveries/${BOB}/inbox/d3`)),
    );
    await assertSucceeds(
      deleteDoc(doc(as(BOB), `signalKeyDeliveries/${BOB}/inbox/d3`)),
    );
  });

  it('keeps a delivery write-once', async () => {
    await seed((db) =>
      setDoc(doc(db, `signalKeyDeliveries/${BOB}/inbox/d4`), {
        senderUid: ALICE,
        threadId: 'g1',
        type: 'senderKeyDistribution',
        payload: 'sealed',
        createdAt: 1,
      }),
    );
    await assertFails(
      updateDoc(doc(as(ALICE), `signalKeyDeliveries/${BOB}/inbox/d4`), {
        payload: 'swapped',
      }),
    );
  });

  it('keeps the key backup strictly owner-only', async () => {
    // This blob is the identity key under a passphrase. A reader gets
    // unlimited offline guesses at it, so nobody but its owner may fetch it.
    await seed((db) =>
      setDoc(doc(db, `signalBackups/${ALICE}`), { blob: 'sealed', salt: 's' }),
    );
    await assertSucceeds(getDoc(doc(as(ALICE), `signalBackups/${ALICE}`)));
    await assertFails(getDoc(doc(as(BOB), `signalBackups/${ALICE}`)));
    await assertFails(
      setDoc(doc(as(BOB), `signalBackups/${ALICE}`), { blob: 'swapped' }),
    );
  });

  it('denies an unauthenticated reader entirely', async () => {
    await seed((db) =>
      setDoc(doc(db, `signalIdentities/${ALICE}`), { registrationId: 1 }),
    );
    await assertFails(getDoc(doc(anonymous(), `signalIdentities/${ALICE}`)));
  });
});

describe('per-owner collections', () => {
  it('lets the owner write their own push token', async () => {
    await assertSucceeds(
      setDoc(doc(as(BOB), `pushTokens/${BOB}`), {
        token: 'tok',
        platform: 'ios',
      }),
    );
  });

  it("denies writing another user's push token", async () => {
    await assertFails(
      setDoc(doc(as(BOB), `pushTokens/${ALICE}`), {
        token: 'stolen',
        platform: 'ios',
      }),
    );
  });

  it('lets any signed-in user read a profile but only the owner write it', async () => {
    await seed((db) => setDoc(doc(db, `userProfiles/${ALICE}`), { name: 'Alice' }));
    await assertSucceeds(getDoc(doc(as(DAVE), `userProfiles/${ALICE}`)));
    await assertFails(
      setDoc(doc(as(DAVE), `userProfiles/${ALICE}`), { name: 'Hacked' }),
    );
  });

  it('keeps the shared music catalog read-only', async () => {
    await seed((db) =>
      setDoc(doc(db, 'statusMusicTracks/t1'), { title: 'Song', artist: 'X' }),
    );
    await assertSucceeds(getDoc(doc(as(BOB), 'statusMusicTracks/t1')));
    await assertFails(
      setDoc(doc(as(BOB), 'statusMusicTracks/t2'), { title: 'Injected' }),
    );
  });
});
