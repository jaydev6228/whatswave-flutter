import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/app/theme/app_theme.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/utils/user_profile_lookup.dart';
import 'package:whatswave/features/calls/application/calls_controller.dart';
import 'package:whatswave/features/calls/data/fake_calls_repository.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/presentation/contact_info_screen.dart';
import 'package:whatswave/features/communities/application/communities_controller.dart';
import 'package:whatswave/features/communities/data/fake_communities_repository.dart';
import 'package:whatswave/features/updates/application/updates_controller.dart';
import 'package:whatswave/features/updates/data/fake_updates_repository.dart';

/// Publishes whatever [phoneNumber] the test asks for on the contact's
/// `userProfiles` document -- null stands for a contact whose own session
/// has never written the field (nobody else is allowed to).
class _ProfileRepository extends FakeChatRepository {
  _ProfileRepository({this.phoneNumber})
      : super(latency: Duration.zero);

  final String? phoneNumber;

  @override
  Future<UserProfileSnapshot?> fetchContactProfile(String uid) async {
    return UserProfileSnapshot(
      name: 'Ava Patel',
      about: 'Shipping launch polish and keeping reviews calm.',
      phoneNumber: phoneNumber,
    );
  }
}

Future<void> _pumpContactInfo(
  WidgetTester tester, {
  String? publishedPhone,
  bool loadContacts = true,
}) async {
  final chats = ChatsController(
    repository: _ProfileRepository(phoneNumber: publishedPhone),
    permissionService: MemoryAppPermissionService(),
  );
  final communities = CommunitiesController(
    repository: FakeCommunitiesRepository(latency: Duration.zero),
  );
  await chats.ensureLoaded();
  if (loadContacts) {
    // The app shell builds every tab up front, so Communities has always
    // loaded before Contact info can be opened.
    await communities.loadOverview();
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(),
      home: ContactInfoScreen(
        controller: chats,
        communitiesController: communities,
        callsController: CallsController(
          repository: FakeCallsRepository(latency: Duration.zero),
        ),
        updatesController: UpdatesController(
          repository: FakeUpdatesRepository(latency: Duration.zero),
        ),
        threadId: 'ava-patel',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('falls back to the device contact number when the published '
      'profile has none', (tester) async {
    await _pumpContactInfo(tester);

    expect(find.byKey(const Key('contact_info_phone_row')), findsOneWidget);
    expect(find.text('+81 90 3000 1122'), findsOneWidget);
  });

  testWidgets('the published profile number wins over the device contact',
      (tester) async {
    await _pumpContactInfo(tester, publishedPhone: '+81 90 9999 0000');

    expect(find.text('+81 90 9999 0000'), findsOneWidget);
    expect(find.text('+81 90 3000 1122'), findsNothing);
  });

  testWidgets('no number anywhere means no row, not an empty one',
      (tester) async {
    // Stands in for contacts permission never granted: nothing loaded, so
    // the fallback yields nothing.
    await _pumpContactInfo(tester, loadContacts: false);

    expect(find.byKey(const Key('contact_info_phone_row')), findsNothing);
  });
}
