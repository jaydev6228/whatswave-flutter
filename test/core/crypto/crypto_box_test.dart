import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/crypto/crypto_box.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('seal/open with an explicit key', () {
    final box = CryptoBox();
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('round-trips', () {
      final sealed = box.sealWith(key, bytes('a private message'));
      expect(utf8.decode(box.openWith(key, sealed)), 'a private message');
    });

    test('produces different ciphertext each time for the same plaintext', () {
      // A fresh nonce per seal. Reusing one under AES-GCM is catastrophic --
      // it leaks the XOR of the plaintexts and breaks the authenticator.
      final a = box.sealWith(key, bytes('same'));
      final b = box.sealWith(key, bytes('same'));
      expect(a, isNot(equals(b)));
      expect(utf8.decode(box.openWith(key, a)), 'same');
      expect(utf8.decode(box.openWith(key, b)), 'same');
    });

    test('refuses a wrong key', () {
      final sealed = box.sealWith(key, bytes('secret'));
      final wrong = Uint8List.fromList(List<int>.filled(32, 9));
      expect(
        () => box.openWith(wrong, sealed),
        throwsA(isA<CryptoBoxException>()),
      );
    });

    test('refuses altered ciphertext rather than returning garbage', () {
      // The authentication half of AEAD: a single flipped bit must fail
      // loudly, not decrypt to something plausible.
      final sealed = box.sealWith(key, bytes('transfer 100'));
      final tampered = Uint8List.fromList(sealed);
      tampered[tampered.length - 5] ^= 0x01;
      expect(
        () => box.openWith(key, tampered),
        throwsA(isA<CryptoBoxException>()),
      );
    });

    test('refuses a truncated blob', () {
      expect(
        () => box.openWith(key, Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<CryptoBoxException>()),
      );
    });

    test('binds additional authenticated data', () {
      // Used by the passphrase backup so its KDF parameters cannot be
      // downgraded by anyone able to rewrite the document.
      final sealed = box.sealWith(key, bytes('payload'), aad: bytes('v1'));
      expect(utf8.decode(box.openWith(key, sealed, aad: bytes('v1'))),
          'payload');
      expect(
        () => box.openWith(key, sealed, aad: bytes('v2')),
        throwsA(isA<CryptoBoxException>()),
      );
    });

    test('handles empty plaintext', () {
      final sealed = box.sealWith(key, Uint8List(0));
      expect(box.openWith(key, sealed), isEmpty);
    });
  });

  group('device-local key', () {
    test('is created once and reused', () async {
      final box = CryptoBox();
      final first = await box.localDataKey();
      final second = await box.localDataKey();
      expect(first, equals(second));
      expect(first.length, 32);
    });

    test('survives a new CryptoBox over the same storage', () async {
      final first = await CryptoBox().localDataKey();
      // A fresh instance means no in-memory cache -- this reads it back.
      final second = await CryptoBox().localDataKey();
      expect(second, equals(first));
    });

    test('round-trips through the convenience base64 helpers', () async {
      final box = CryptoBox();
      final sealed = await box.sealToBase64('{"text":"hello"}');
      expect(sealed, isNot(contains('hello')));
      expect(await box.openFromBase64(sealed), '{"text":"hello"}');
    });

    test('destroying the key makes previously sealed data unreadable',
        () async {
      // This is what makes sign-out a real wipe rather than best-effort:
      // one delete, and every local store keyed by it is dead.
      final box = CryptoBox();
      final sealed = await box.sealToBase64('previous user history');
      await box.destroyLocalDataKey();

      final afterWipe = CryptoBox();
      expect(
        () => afterWipe.openFromBase64(sealed),
        throwsA(isA<CryptoBoxException>()),
      );
    });

    test('concurrent first use cannot produce two different keys', () async {
      // Caching only the resolved key let two seals race on a fresh install:
      // both found no stored key, both generated their own, both wrote, and
      // whatever the loser sealed became permanently unopenable.
      final box = CryptoBox();
      final sealed = await Future.wait(<Future<Uint8List>>[
        box.seal(bytes('one')),
        box.seal(bytes('two')),
        box.seal(bytes('three')),
      ]);

      expect(utf8.decode(await box.open(sealed[0])), 'one');
      expect(utf8.decode(await box.open(sealed[1])), 'two');
      expect(utf8.decode(await box.open(sealed[2])), 'three');

      // And a fresh box over the same storage must agree with all of them.
      expect(utf8.decode(await CryptoBox().open(sealed[0])), 'one');
    });

    test('replaces a corrupt stored key instead of failing forever', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        'ww_local_data_key_v1': base64Encode(<int>[1, 2, 3]), // wrong length
      });
      final key = await CryptoBox().localDataKey();
      expect(key.length, 32);
    });
  });
}
