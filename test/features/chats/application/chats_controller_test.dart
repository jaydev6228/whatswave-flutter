import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/core/permissions/app_permission_service.dart';
import 'package:whatswave/core/permissions/device_location_service.dart';
import 'package:whatswave/core/sample/demo_data.dart';
import 'package:whatswave/features/chats/application/chats_controller.dart';
import 'package:whatswave/features/chats/data/chat_repository.dart';
import 'package:whatswave/features/chats/data/fake_chat_repository.dart';
import 'package:whatswave/features/chats/domain/chat_attachment.dart';
import 'package:whatswave/features/chats/domain/chat_thread.dart';

void main() {
  group('ChatsController', () {
    late ChatsController controller;

    setUp(() {
      controller = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
      );
    });

    test('loads chats and tracks active versus archived threads', () async {
      await controller.loadThreads();

      expect(controller.hasLoaded, isTrue);
      expect(controller.activeCount, 4);
      expect(controller.archivedCount, 1);
      expect(controller.visibleThreads.every((thread) => !thread.isArchived),
          isTrue);
      expect(controller.visibleThreads.first.name, 'Design Sprint');
    });

    test('filters by unread state and search query', () async {
      await controller.loadThreads();

      controller.updateFilter(ChatListFilter.unread);
      expect(
        controller.visibleThreads.map((thread) => thread.name),
        containsAll(<String>['Ava Patel', 'Design Sprint', 'Family']),
      );
      expect(
        controller.visibleThreads.any((thread) => thread.name == 'Product Ops'),
        isFalse,
      );

      controller.updateSearchQuery('voice note');
      expect(controller.visibleThreads.single.name, 'Family');
    });

    test('archives and unarchives threads across inbox views', () async {
      await controller.loadThreads();

      await controller.setThreadArchived(
          threadId: 'ava-patel', isArchived: true);
      expect(controller.threadById('ava-patel')?.isArchived, isTrue);
      expect(
        controller.visibleThreads.any((thread) => thread.id == 'ava-patel'),
        isFalse,
      );

      controller.toggleArchivedOnly();
      expect(
        controller.visibleThreads.any((thread) => thread.id == 'ava-patel'),
        isTrue,
      );

      await controller.setThreadArchived(
          threadId: 'ava-patel', isArchived: false);
      expect(controller.showArchivedOnly, isFalse);
      expect(controller.threadById('ava-patel')?.isArchived, isFalse);
    });

    test('marks unread chats as read when opened', () async {
      await controller.loadThreads();

      expect(controller.threadById('family')?.unreadCount, 12);

      await controller.openThread('family');

      expect(controller.threadById('family')?.unreadCount, 0);
    });

    test('sends text and attachment messages into a thread', () async {
      await controller.loadThreads();

      await controller.sendTextMessage(
        threadId: 'ava-patel',
        text: 'I will send the polished handoff in five.',
      );
      await controller.sendAttachmentMessage(
        threadId: 'ava-patel',
        attachments: const [
          ChatAttachment(
            id: 'test-photo',
            type: ChatAttachmentType.photo,
            title: 'Polished handoff',
            details: 'Ready for review',
            tintColor: Color(0xFF25D366),
            aspectRatio: 1.1,
          ),
        ],
      );

      final thread = controller.threadById('ava-patel');
      expect(thread, isNotNull);
      expect(
          thread!.messages.last.attachments.single.title, 'Polished handoff');
      expect(thread.messages[thread.messages.length - 2].text,
          'I will send the polished handoff in five.');
    });

    test('surfaces send failures and keeps the existing thread history intact',
        () async {
      final failingController = ChatsController(
        repository: _SendFailingChatRepository(),
      );

      await failingController.loadThreads();
      final originalCount =
          failingController.threadById('ava-patel')!.messages.length;

      final didSend = await failingController.sendTextMessage(
        threadId: 'ava-patel',
        text: 'This should fail.',
      );

      expect(didSend, isFalse);
      expect(
        failingController.errorMessage,
        'Message service offline',
      );
      expect(
        failingController.threadById('ava-patel')!.messages.length,
        originalCount,
      );
    });

    test('surfaces repository failures on initial load', () async {
      final failingController = ChatsController(
        repository: _FailingChatRepository(),
      );

      await failingController.loadThreads();

      expect(failingController.hasLoaded, isFalse);
      expect(failingController.visibleThreads, isEmpty);
      expect(failingController.errorMessage, 'Network went away');
    });

    test('shares the current location once permission is granted', () async {
      final locationController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      );
      await locationController.loadThreads();

      final outcome = await locationController.sendCurrentLocation(
        threadId: 'ava-patel',
      );

      expect(outcome, LocationShareOutcome.sent);
      final attachment = locationController
          .threadById('ava-patel')!
          .messages
          .last
          .attachments
          .single;
      expect(attachment.type, ChatAttachmentType.location);
      expect(attachment.latitude, 35.6595);
      expect(attachment.longitude, 139.7005);
      expect(attachment.hasCoordinates, isTrue);
    });

    test(
        'reports permission-denied without touching errorMessage or sending anything',
        () async {
      final deniedController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(
          grantLocationOnRequest: false,
        ),
        locationService: const _FakeDeviceLocationService(
          fix: DeviceLocationFix(latitude: 35.6595, longitude: 139.7005),
        ),
      );
      await deniedController.loadThreads();
      final originalCount =
          deniedController.threadById('ava-patel')!.messages.length;

      final outcome =
          await deniedController.sendCurrentLocation(threadId: 'ava-patel');

      expect(outcome, LocationShareOutcome.permissionDenied);
      expect(deniedController.errorMessage, isNull);
      expect(
        deniedController.threadById('ava-patel')!.messages.length,
        originalCount,
      );
    });

    test('surfaces device location failures', () async {
      final failingLocationController = ChatsController(
        repository: FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        ),
        permissionService: MemoryAppPermissionService(),
        locationService: const _FakeDeviceLocationService(
          error: DeviceLocationException('GPS is unavailable right now.'),
        ),
      );
      await failingLocationController.loadThreads();

      final outcome = await failingLocationController.sendCurrentLocation(
        threadId: 'ava-patel',
      );

      expect(outcome, LocationShareOutcome.failed);
      expect(failingLocationController.errorMessage, isNull);
      expect(
        failingLocationController.locationFailureMessage,
        'GPS is unavailable right now.',
      );
    });
  });
}

class _FakeDeviceLocationService implements DeviceLocationService {
  const _FakeDeviceLocationService({this.fix, this.error});

  final DeviceLocationFix? fix;
  final DeviceLocationException? error;

  @override
  Future<DeviceLocationFix> getCurrentLocation() async {
    if (error != null) {
      throw error!;
    }
    return fix!;
  }
}

class _FailingChatRepository implements ChatRepository {
  @override
  Future<List<ChatThread>> fetchThreads() {
    throw const ChatRepositoryException('Network went away');
  }

  @override
  Stream<List<ChatThread>>? watchThreads() => null;

  @override
  Future<List<ChatThread>> deleteThread(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> markThreadRead(String threadId) {
    throw UnimplementedError();
  }

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) {
    throw UnimplementedError();
  }
}

class _SendFailingChatRepository implements ChatRepository {
  _SendFailingChatRepository()
      : _delegate = FakeChatRepository(
          initialThreads: DemoData.buildChatThreads(),
          latency: Duration.zero,
        );

  final FakeChatRepository _delegate;

  @override
  Future<List<ChatThread>> fetchThreads() => _delegate.fetchThreads();

  @override
  Stream<List<ChatThread>>? watchThreads() => _delegate.watchThreads();

  @override
  Future<List<ChatThread>> deleteThread(String threadId) =>
      _delegate.deleteThread(threadId);

  @override
  Future<ChatThread> startThread({
    required String participantUid,
    required String participantName,
    required String avatarLabel,
    required Color accentColor,
  }) {
    return _delegate.startThread(
      participantUid: participantUid,
      participantName: participantName,
      avatarLabel: avatarLabel,
      accentColor: accentColor,
    );
  }

  @override
  Future<List<ChatThread>> markThreadRead(String threadId) =>
      _delegate.markThreadRead(threadId);

  @override
  Future<ChatThread> createGroup({
    required String name,
    required List<String> memberUids,
  }) =>
      _delegate.createGroup(name: name, memberUids: memberUids);

  @override
  Future<List<ChatThread>> sendAttachmentMessage({
    required String threadId,
    required List<ChatAttachment> attachments,
    String? caption,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> sendTextMessage({
    required String threadId,
    required String text,
  }) {
    throw const ChatRepositoryException('Message service offline');
  }

  @override
  Future<List<ChatThread>> setThreadArchived({
    required String threadId,
    required bool isArchived,
  }) =>
      _delegate.setThreadArchived(
        threadId: threadId,
        isArchived: isArchived,
      );
}
