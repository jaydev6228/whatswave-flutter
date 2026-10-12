import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/crypto/media_crypto.dart';

void main() {
  late Directory dir;
  // Inline: these cover the cipher, not the isolate hop. One test below
  // exercises the real (isolate) path.
  const crypto = MediaCrypto(inIsolate: false);
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ww_media_crypto');
    addTearDown(() => dir.delete(recursive: true));
  });

  File file(String name) => File('${dir.path}/$name');

  Future<File> plaintextOf(int bytes) async {
    final random = Random(42);
    final f = file('plain.bin');
    await f.writeAsBytes(
      Uint8List.fromList(List<int>.generate(bytes, (_) => random.nextInt(256))),
    );
    return f;
  }

  test('round-trips a small file', () async {
    final source = await plaintextOf(1024);
    final sealed = file('sealed.bin');
    final opened = file('opened.bin');

    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    await crypto.decryptFile(
        source: sealed, destination: opened, mediaKey: key);

    expect(await opened.readAsBytes(), equals(await source.readAsBytes()));
  });

  test('round-trips a file larger than one chunk', () async {
    // Crosses the 64 KiB boundary several times, which is where an
    // off-by-one in the streaming maths would show up.
    final source = await plaintextOf(MediaCrypto.chunkSize * 3 + 1234);
    final sealed = file('sealed.bin');
    final opened = file('opened.bin');

    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    await crypto.decryptFile(
        source: sealed, destination: opened, mediaKey: key);

    expect(await opened.length(), await source.length());
    expect(await opened.readAsBytes(), equals(await source.readAsBytes()));
  });

  test('handles an empty file', () async {
    final source = await plaintextOf(0);
    final sealed = file('sealed.bin');
    final opened = file('opened.bin');

    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    await crypto.decryptFile(
        source: sealed, destination: opened, mediaKey: key);

    expect(await opened.length(), 0);
  });

  test('the ciphertext does not contain the plaintext', () async {
    final source = file('plain.bin');
    await source.writeAsString('SECRET PAYLOAD MARKER');
    final sealed = file('sealed.bin');

    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);

    expect(
      String.fromCharCodes(await sealed.readAsBytes()),
      isNot(contains('SECRET PAYLOAD MARKER')),
    );
  });

  test('adds exactly the MAC to the size', () async {
    final source = await plaintextOf(5000);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    expect(await sealed.length(), 5000 + 32);
  });

  test('refuses a wrong key', () async {
    final source = await plaintextOf(2048);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);

    final wrong = Uint8List.fromList(List<int>.filled(32, 3));
    await expectLater(
      crypto.decryptFile(
          source: sealed, destination: file('out.bin'), mediaKey: wrong),
      throwsA(isA<MediaCryptoException>()),
    );
  });

  test('refuses tampered bytes rather than decrypting them', () async {
    // The integrity half. Without the MAC, CTR mode would happily decrypt
    // flipped bits into flipped plaintext -- an attacker who can write to
    // Storage could alter an image in place.
    final source = await plaintextOf(4096);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);

    final bytes = await sealed.readAsBytes();
    bytes[100] ^= 0x01;
    await sealed.writeAsBytes(bytes);

    await expectLater(
      crypto.decryptFile(
          source: sealed, destination: file('out.bin'), mediaKey: key),
      throwsA(isA<MediaCryptoException>()),
    );
  });

  test('refuses a tampered MAC', () async {
    final source = await plaintextOf(1024);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);

    final bytes = await sealed.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF;
    await sealed.writeAsBytes(bytes);

    await expectLater(
      crypto.decryptFile(
          source: sealed, destination: file('out.bin'), mediaKey: key),
      throwsA(isA<MediaCryptoException>()),
    );
  });

  test('refuses a truncated file', () async {
    final source = await plaintextOf(4096);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);

    final bytes = await sealed.readAsBytes();
    await sealed.writeAsBytes(bytes.sublist(0, bytes.length - 100));

    await expectLater(
      crypto.decryptFile(
          source: sealed, destination: file('out.bin'), mediaKey: key),
      throwsA(isA<MediaCryptoException>()),
    );
  });

  test('writes no plaintext when verification fails', () async {
    // The MAC is checked before a single byte is written, so a tampered
    // download never reaches the viewer even partially.
    final source = await plaintextOf(4096);
    final sealed = file('sealed.bin');
    await crypto.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    final bytes = await sealed.readAsBytes();
    bytes[10] ^= 0x01;
    await sealed.writeAsBytes(bytes);

    final out = file('out.bin');
    await expectLater(
      crypto.decryptFile(source: sealed, destination: out, mediaKey: key),
      throwsA(isA<MediaCryptoException>()),
    );
    expect(out.existsSync(), isFalse);
  });

  test('rejects a key of the wrong length', () async {
    final source = await plaintextOf(16);
    await expectLater(
      crypto.encryptFile(
        source: source,
        destination: file('sealed.bin'),
        mediaKey: Uint8List.fromList(<int>[1, 2, 3]),
      ),
      throwsA(isA<MediaCryptoException>()),
    );
  });

  test('round-trips through the isolate, which is how the app runs it',
      () async {
    // The default path. AES over a photo on the main isolate is roughly a
    // second of frozen UI, so production always hops off it.
    final source = await plaintextOf(64 * 1024);
    final sealed = file('sealed.bin');
    final opened = file('opened.bin');
    const isolated = MediaCrypto();

    await isolated.encryptFile(
        source: source, destination: sealed, mediaKey: key);
    await isolated.decryptFile(
        source: sealed, destination: opened, mediaKey: key);

    expect(await opened.readAsBytes(), equals(await source.readAsBytes()));
  });

  test('two keys produce different ciphertext for the same input', () async {
    final source = await plaintextOf(2048);
    final a = file('a.bin');
    final b = file('b.bin');
    await crypto.encryptFile(source: source, destination: a, mediaKey: key);
    await crypto.encryptFile(
      source: source,
      destination: b,
      mediaKey: Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)),
    );
    expect(await a.readAsBytes(), isNot(equals(await b.readAsBytes())));
  });
}
