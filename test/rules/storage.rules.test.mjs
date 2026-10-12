// Security-rules tests for storage.rules.
//
// Covers the per-owner write gates and the upload ceilings added alongside
// them. The content-type allowlist on the image-only paths is the part worth
// testing deliberately: an object stored with a text/html content type is
// served as HTML from the Storage origin, so its download URL would host
// whatever markup was uploaded. Pinning the type is what prevents that, and
// it only works if the rule really rejects everything else.
//
// Not covered here: groupPhotos and communityPhotos, whose rules call
// firestore.get() to check the admin roster. Those are cross-service and
// need Firestore seeded from this same environment -- worth adding, but they
// are not what the size/content-type change touched.
//
// Run with: npm run test:rules

import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, '..', '..');

const ALICE = 'alice';
const BOB = 'bob';

const png = (bytes) => new Uint8Array(bytes);
const IMAGE = { contentType: 'image/png' };

let testEnv;

const as = (uid) => testEnv.authenticatedContext(uid).storage();
const anonymous = () => testEnv.unauthenticatedContext().storage();

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-whatswave',
    storage: {
      rules: readFileSync(join(projectRoot, 'storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('profilePhotos', () => {
  it('lets the owner upload their own avatar', async () => {
    await assertSucceeds(
      uploadBytes(ref(as(ALICE), `profilePhotos/${ALICE}/avatar.png`), png(64), IMAGE),
    );
  });

  it("denies uploading over another user's avatar", async () => {
    await assertFails(
      uploadBytes(ref(as(BOB), `profilePhotos/${ALICE}/avatar.png`), png(64), IMAGE),
    );
  });

  it('denies an avatar larger than the 8MB ceiling', async () => {
    await assertFails(
      uploadBytes(
        ref(as(ALICE), `profilePhotos/${ALICE}/huge.png`),
        png(9 * 1024 * 1024),
        IMAGE,
      ),
    );
  });

  it('denies a non-image content type on an image-only path', async () => {
    // The stored-XSS guard: these bytes are markup, and without the
    // allowlist they would be served as text/html from the Storage origin.
    await assertFails(
      uploadBytes(
        ref(as(ALICE), `profilePhotos/${ALICE}/payload.html`),
        new TextEncoder().encode('<script>alert(1)</script>'),
        { contentType: 'text/html' },
      ),
    );
  });

  it('denies an anonymous upload', async () => {
    await assertFails(
      uploadBytes(ref(anonymous(), `profilePhotos/${ALICE}/avatar.png`), png(64), IMAGE),
    );
  });
});

describe('statusMedia', () => {
  it('lets the owner upload their own status video', async () => {
    await assertSucceeds(
      uploadBytes(ref(as(ALICE), `statusMedia/${ALICE}/clip.mp4`), png(128), {
        contentType: 'video/mp4',
      }),
    );
  });

  it("denies writing into another user's status folder", async () => {
    await assertFails(
      uploadBytes(ref(as(BOB), `statusMedia/${ALICE}/clip.mp4`), png(128), {
        contentType: 'video/mp4',
      }),
    );
  });

  it('denies a document masquerading as status media', async () => {
    await assertFails(
      uploadBytes(ref(as(ALICE), `statusMedia/${ALICE}/notes.pdf`), png(128), {
        contentType: 'application/pdf',
      }),
    );
  });
});

describe('chatMedia', () => {
  it('accepts an arbitrary document, which is a real feature here', async () => {
    // Deliberately no content-type allowlist on this path: sending a
    // Word/Excel/PDF attachment is supported, and encrypted attachments
    // will arrive as application/octet-stream.
    await assertSucceeds(
      uploadBytes(ref(as(ALICE), 'chatMedia/t1/m1-a1.pdf'), png(256), {
        contentType: 'application/pdf',
      }),
    );
  });

  it('denies an anonymous upload', async () => {
    await assertFails(
      uploadBytes(ref(anonymous(), 'chatMedia/t1/m1-a2.pdf'), png(256)),
    );
  });

  it('never allows deleting chat media', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), 'chatMedia/t1/seeded.png'), png(64), IMAGE);
    });
    const { deleteObject } = await import('firebase/storage');
    await assertFails(deleteObject(ref(as(ALICE), 'chatMedia/t1/seeded.png')));
  });
});

describe('shared catalogs and the default deny', () => {
  it('lets a signed-in user read the music catalog but never write it', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), 'statusMusic/song.mp3'), png(64), {
        contentType: 'audio/mpeg',
      });
    });
    await assertSucceeds(getBytes(ref(as(BOB), 'statusMusic/song.mp3')));
    await assertFails(
      uploadBytes(ref(as(BOB), 'statusMusic/injected.mp3'), png(64), {
        contentType: 'audio/mpeg',
      }),
    );
  });

  it('denies an unknown path through the catch-all', async () => {
    await assertFails(
      uploadBytes(ref(as(ALICE), 'somewhere/else/file.png'), png(64), IMAGE),
    );
  });
});
