import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/shared/widgets/avatar_badge.dart';

/// Fails every request immediately instead of attempting a real network
/// call -- widget tests run without network access, and Image.network
/// otherwise hangs waiting on a real (never-arriving) response.
class _ThrowingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const SocketException('No network in tests.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shows initials when avatarUrl is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AvatarBadge(label: 'Jamie Doe', color: Colors.teal),
        ),
      ),
    );

    expect(find.text('JA'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows initials when avatarUrl is empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AvatarBadge(label: 'Jamie Doe', color: Colors.teal, avatarUrl: ''),
        ),
      ),
    );

    expect(find.text('JA'), findsOneWidget);
  });

  testWidgets('renders a network image when avatarUrl is set', (tester) async {
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarBadge(
              label: 'Jamie Doe',
              color: Colors.teal,
              avatarUrl: 'https://firebasestorage.example/avatar.jpg',
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect(
        (image.image as NetworkImage).url,
        'https://firebasestorage.example/avatar.jpg',
      );
    }, createHttpClient: (context) => _ThrowingHttpClient());
  });

  testWidgets('falls back to initials if the network image fails to load',
      (tester) async {
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarBadge(
              label: 'Jamie Doe',
              color: Colors.teal,
              avatarUrl: 'https://firebasestorage.example/avatar.jpg',
            ),
          ),
        ),
      );
      // Let the failed image request resolve to an error frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('JA'), findsOneWidget);
    }, createHttpClient: (context) => _ThrowingHttpClient());
  });
}
