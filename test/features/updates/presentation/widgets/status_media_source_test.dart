import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/updates/presentation/widgets/status_media_source.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() {
  group('isRemoteStatusMediaPath', () {
    test('true for https:// and http:// paths', () {
      expect(
        isRemoteStatusMediaPath('https://firebasestorage.example/x.jpg'),
        isTrue,
      );
      expect(isRemoteStatusMediaPath('http://example.com/x.jpg'), isTrue);
    });

    test('false for local, bundled, and empty paths', () {
      expect(isRemoteStatusMediaPath('/var/mobile/media.jpg'), isFalse);
      expect(isRemoteStatusMediaPath('asset://media/demo.jpg'), isFalse);
      expect(isRemoteStatusMediaPath(''), isFalse);
    });
  });

  group('statusMediaSourceExists', () {
    test('a remote URL always counts as existing (no local disk check)', () {
      expect(
        statusMediaSourceExists('https://firebasestorage.example/x.jpg'),
        isTrue,
      );
    });

    test('a nonexistent local path does not exist', () {
      expect(
        statusMediaSourceExists('/definitely/not/a/real/path.jpg'),
        isFalse,
      );
    });

    test('empty path does not exist', () {
      expect(statusMediaSourceExists('  '), isFalse);
    });
  });

  group('imageProviderForStatusMediaPath', () {
    test('a remote URL resolves to a disk-cached provider', () async {
      // Was NetworkImage, whose cache is memory-only -- every cold start
      // re-downloaded the same status photo. Only used once the cache has
      // proven itself, hence the await.
      await ensureStatusMediaDiskCacheReady();
      final provider = imageProviderForStatusMediaPath(
        'https://firebasestorage.example/x.jpg',
      );
      expect(provider, isA<CachedNetworkImageProvider>());
      expect((provider as CachedNetworkImageProvider).url,
          'https://firebasestorage.example/x.jpg');
    });

    test('a bundled asset:// path resolves to an AssetImage', () {
      final provider =
          imageProviderForStatusMediaPath('asset://media/demo.jpg');
      expect(provider, isA<AssetImage>());
    });

    test('a nonexistent local path resolves to null', () {
      final provider =
          imageProviderForStatusMediaPath('/definitely/not/real.jpg');
      expect(provider, isNull);
    });

    test('an empty path resolves to null', () {
      expect(imageProviderForStatusMediaPath(''), isNull);
    });
  });
}
