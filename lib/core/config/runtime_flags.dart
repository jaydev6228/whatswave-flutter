import 'package:flutter/foundation.dart';

const bool _kRequestedDemoSurfaces = bool.fromEnvironment(
  'WW_ENABLE_DEMO_SURFACES',
  defaultValue: true,
);

/// Demo and QA-only surfaces are never allowed in release or TestFlight builds.
const bool kEnableDemoSurfaces = !kReleaseMode && _kRequestedDemoSurfaces;

/// Seeded session restore is also restricted to non-release builds.
const bool kEnableDemoRestoreSession =
    !kReleaseMode && bool.fromEnvironment('WW_DEMO_RESTORE_SESSION');

/// Whether chat attachments are encrypted before upload.
///
/// On. `_uploadAttachmentMedia` encrypts to a temp file with AES-256-CTR +
/// HMAC, uploads the ciphertext, caches the ciphertext, and carries the key
/// inside the sealed message envelope -- so Storage holds bytes nobody
/// outside the conversation can read.
///
/// Every consumer now resolves through `resolveAttachmentMediaPath`, which
/// verifies the MAC before writing any plaintext: the thumbnail, the
/// full-screen viewer, the document openers, voice-note playback and
/// save-to-gallery. `media_transfer_chrome` deliberately still works on the
/// raw URL, because the disk cache is keyed by URL and holds the ciphertext.
///
/// Message text and attachment *metadata* are encrypted regardless of this
/// flag; it governs only the media bytes in Storage.
const bool kEncryptAttachmentMedia = true;
