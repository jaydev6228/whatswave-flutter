import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class MediaCryptoException implements Exception {
  const MediaCryptoException(this.message);

  final String message;

  @override
  String toString() => 'MediaCryptoException: $message';
}

/// Encrypts attachment bytes before they are uploaded.
///
/// AES-256-CTR with a trailing HMAC-SHA256, rather than AES-GCM, and the
/// reason is size. GCM must buffer an entire ciphertext and verify its tag
/// before it will yield a single byte, which on a 200 MB video means
/// holding 200 MB in memory. CTR decrypts in a stream and the MAC is
/// checked over the file as it is read, so memory stays flat regardless of
/// how big the attachment is. It is also the construction WhatsApp uses for
/// exactly this.
///
/// One random [mediaKey] per attachment, carried inside the encrypted
/// message envelope -- so the key reaches precisely the people who can read
/// the message, and Storage never sees it.
class MediaCrypto {
  /// [inIsolate] false runs the work inline. Only tests want that -- in the
  /// app this must stay true: AES over a photo in pure Dart takes roughly
  /// 120ms per megabyte on a fast desktop and several times that on a
  /// phone, so a 5MB photo on the main isolate is about a second of frozen
  /// UI and a 20MB video is several. That is the difference between "send"
  /// feeling instant and feeling broken.
  const MediaCrypto({this.inIsolate = true});

  final bool inIsolate;

  /// Bytes processed per step. Large enough to keep syscalls down, small
  /// enough that memory does not track file size.
  static const int chunkSize = 64 * 1024;
  static const int _macLengthBytes = 32;
  static const int _ivLengthBytes = 16;
  static const int keyLengthBytes = 32;

  static final Uint8List _hkdfInfo =
      Uint8List.fromList(utf8.encode('WhatsWave Media Keys'));

  /// Three independent subkeys from the one media key, so the cipher key
  /// and the MAC key are never the same bytes.
  _MediaKeys _expand(Uint8List mediaKey) {
    if (mediaKey.length != keyLengthBytes) {
      throw const MediaCryptoException('A media key must be 32 bytes.');
    }
    final derivator = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(mediaKey, 80, null, _hkdfInfo));
    final out = derivator.process(Uint8List(0));
    return _MediaKeys(
      iv: Uint8List.sublistView(out, 0, _ivLengthBytes),
      cipherKey: Uint8List.sublistView(out, 16, 48),
      macKey: Uint8List.sublistView(out, 48, 80),
    );
  }

  CTRStreamCipher _cipher(_MediaKeys keys) => CTRStreamCipher(AESEngine())
    ..init(true, ParametersWithIV<KeyParameter>(
      KeyParameter(keys.cipherKey),
      keys.iv,
    ));

  /// Encrypts [source] to [destination], appending the MAC.
  ///
  /// The output is `ciphertext ‖ mac`, with the MAC taken over
  /// `iv ‖ ciphertext` so a truncated or spliced file fails verification
  /// rather than decrypting to plausible garbage.
  Future<void> encryptFile({
    required File source,
    required File destination,
    required Uint8List mediaKey,
  }) {
    final request = FileCryptoRequest(
      sourcePath: source.path,
      destinationPath: destination.path,
      mediaKey: mediaKey,
    );
    return inIsolate
        ? compute(encryptFileRequest, request)
        : encryptFileRequest(request);
  }

  Future<void> decryptFile({
    required File source,
    required File destination,
    required Uint8List mediaKey,
  }) {
    final request = FileCryptoRequest(
      sourcePath: source.path,
      destinationPath: destination.path,
      mediaKey: mediaKey,
    );
    return inIsolate
        ? compute(decryptFileRequest, request)
        : decryptFileRequest(request);
  }

  Future<void> _encrypt({
    required File source,
    required File destination,
    required Uint8List mediaKey,
  }) async {
    final keys = _expand(mediaKey);
    final cipher = _cipher(keys);
    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(keys.macKey));
    mac.update(keys.iv, 0, keys.iv.length);

    final sink = destination.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        final input = Uint8List.fromList(chunk);
        final encrypted = Uint8List(input.length);
        cipher.processBytes(input, 0, input.length, encrypted, 0);
        mac.update(encrypted, 0, encrypted.length);
        sink.add(encrypted);
      }
      final digest = Uint8List(_macLengthBytes);
      mac.doFinal(digest, 0);
      sink.add(digest);
    } finally {
      await sink.close();
    }
  }

  /// Decrypts [source] to [destination], verifying as it goes.
  ///
  /// Single pass: the plaintext is written to a sibling temp file while the
  /// MAC is computed, and only moved to [destination] once it verifies.
  /// Unverified plaintext therefore never appears at the destination path,
  /// which was the property of the old verify-then-decrypt version -- at
  /// half the I/O and half the CPU, since that one read the whole file
  /// twice.
  Future<void> _decrypt({
    required File source,
    required File destination,
    required Uint8List mediaKey,
  }) async {
    final keys = _expand(mediaKey);
    final totalLength = await source.length();
    if (totalLength < _macLengthBytes) {
      throw const MediaCryptoException('Encrypted media is too short.');
    }
    final bodyLength = totalLength - _macLengthBytes;

    final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(keys.macKey));
    mac.update(keys.iv, 0, keys.iv.length);
    final cipher = _cipher(keys);

    // Written here, moved to `destination` only once the MAC verifies, so
    // a caller never sees unverified plaintext at the real path.
    final staging = File('${destination.path}.part');
    final sink = staging.openWrite();
    var consumed = 0;
    final expected = Uint8List(_macLengthBytes);
    var expectedFilled = 0;

    try {
      await for (final chunk in source.openRead()) {
        final bytes = Uint8List.fromList(chunk);
        final bodyInChunk = (bodyLength - consumed).clamp(0, bytes.length);
        if (bodyInChunk > 0) {
          final input = Uint8List.sublistView(bytes, 0, bodyInChunk);
          mac.update(input, 0, bodyInChunk);
          final plain = Uint8List(bodyInChunk);
          cipher.processBytes(input, 0, bodyInChunk, plain, 0);
          sink.add(plain);
          consumed += bodyInChunk;
        }
        if (bodyInChunk < bytes.length) {
          final tail = bytes.sublist(bodyInChunk);
          expected.setRange(expectedFilled, expectedFilled + tail.length, tail);
          expectedFilled += tail.length;
        }
      }
    } finally {
      await sink.close();
    }

    final actual = Uint8List(_macLengthBytes);
    mac.doFinal(actual, 0);
    if (!_constantTimeEquals(actual, expected)) {
      if (staging.existsSync()) {
        await staging.delete();
      }
      throw const MediaCryptoException(
        'Encrypted media failed its integrity check.',
      );
    }

    await staging.rename(destination.path);
  }

  /// Comparison that does not leak where two MACs diverge.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _MediaKeys {
  const _MediaKeys({
    required this.iv,
    required this.cipherKey,
    required this.macKey,
  });

  final Uint8List iv;
  final Uint8List cipherKey;
  final Uint8List macKey;
}

/// Everything a file crypto operation needs, in one isolate-transferable
/// object. Paths rather than File handles, because a File does not cross
/// an isolate boundary.
@immutable
class FileCryptoRequest {
  const FileCryptoRequest({
    required this.sourcePath,
    required this.destinationPath,
    required this.mediaKey,
  });

  final String sourcePath;
  final String destinationPath;
  final Uint8List mediaKey;
}

/// Top-level so `compute` can run them off the main isolate.
Future<void> encryptFileRequest(FileCryptoRequest request) =>
    const MediaCrypto(inIsolate: false)._encrypt(
      source: File(request.sourcePath),
      destination: File(request.destinationPath),
      mediaKey: request.mediaKey,
    );

Future<void> decryptFileRequest(FileCryptoRequest request) =>
    const MediaCrypto(inIsolate: false)._decrypt(
      source: File(request.sourcePath),
      destination: File(request.destinationPath),
      mediaKey: request.mediaKey,
    );
