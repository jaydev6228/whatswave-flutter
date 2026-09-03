import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/domain/group_participant.dart';
import 'package:whatswave/features/shared/widgets/avatar_badge.dart';
import 'package:whatswave/features/shared/widgets/composite_group_avatar.dart';

GroupParticipant _participant(String name, {bool isSelf = false}) {
  return GroupParticipant(
    uid: name.toLowerCase(),
    name: name,
    avatarLabel: name,
    accentColor: Colors.teal,
    isSelf: isSelf,
  );
}

Future<void> _pumpAvatar(
  WidgetTester tester,
  List<GroupParticipant> participants,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CompositeGroupAvatar(
            participants: participants,
            fallbackLabel: 'Group Chat',
            fallbackColor: Colors.indigo,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('leaves your own avatar out of the tiles', (tester) async {
    await _pumpAvatar(tester, [
      _participant('Self', isSelf: true),
      _participant('Ana'),
      _participant('Ben'),
      _participant('Cara'),
    ]);

    expect(find.text('SE'), findsNothing);
    expect(find.text('AN'), findsOneWidget);
    expect(find.text('BE'), findsOneWidget);
    expect(find.text('CA'), findsOneWidget);
    expect(find.byType(AvatarBadge), findsNothing);
  });

  testWidgets('you plus one member renders the single-member badge',
      (tester) async {
    await _pumpAvatar(tester, [
      _participant('Self', isSelf: true),
      _participant('Ana'),
    ]);

    expect(find.byType(AvatarBadge), findsOneWidget);
    expect(find.text('AN'), findsOneWidget);
    expect(find.text('SE'), findsNothing);
  });

  testWidgets('a group of only you falls back to the group badge',
      (tester) async {
    await _pumpAvatar(tester, [_participant('Self', isSelf: true)]);

    expect(find.byType(AvatarBadge), findsOneWidget);
    expect(find.text('GR'), findsOneWidget);
    expect(find.text('SE'), findsNothing);
  });

  testWidgets('participant lists without isSelf are unchanged',
      (tester) async {
    await _pumpAvatar(tester, [
      _participant('Ana'),
      _participant('Ben'),
      _participant('Cara'),
      _participant('Dev'),
    ]);

    expect(find.text('AN'), findsOneWidget);
    expect(find.text('BE'), findsOneWidget);
    expect(find.text('CA'), findsOneWidget);
    expect(find.text('DE'), findsOneWidget);
    expect(find.byType(AvatarBadge), findsNothing);
  });
}
