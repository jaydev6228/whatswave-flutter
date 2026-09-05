import 'package:flutter_test/flutter_test.dart';
import 'package:whatswave/features/chats/domain/typing_state.dart';

void main() {
  test('excludes the viewer and stale entries from active typists', () {
    final now = DateTime(2026, 1, 1, 12);

    final typists = resolveActiveTypistsForViewer(
      viewerUid: 'me',
      typingByUid: {
        'me': TypingParticipantState(
          displayName: 'You',
          startedAt: now,
        ),
        'marco': TypingParticipantState(
          displayName: 'Marco',
          startedAt: now.subtract(const Duration(seconds: 2)),
        ),
        'priya': TypingParticipantState(
          displayName: 'Priya',
          startedAt: now.subtract(const Duration(seconds: 30)),
        ),
      },
      now: now,
    );

    expect(typists, hasLength(1));
    expect(typists.single.displayName, 'Marco');
  });

  test('formats chat list labels for direct and group threads', () {
    final marco = TypingParticipantState(
      displayName: 'Marco',
      startedAt: DateTime(2026),
    );

    expect(
      typingListLabel(const [], isGroup: false),
      isEmpty,
    );
    expect(
      typingListLabel([marco], isGroup: false),
      'typing',
    );
    expect(
      typingListLabel([marco], isGroup: true),
      'Marco',
    );
    expect(
      typingListLabel(
        [
          marco,
          TypingParticipantState(
            displayName: 'Priya',
            startedAt: DateTime(2026),
          ),
        ],
        isGroup: true,
      ),
      'Marco and Priya',
    );
  });

  test('formats group and direct conversation typing lines', () {
    expect(
      conversationTypingLine(const [], isGroup: false),
      isEmpty,
    );
    expect(
      conversationTypingLine(
        [
          TypingParticipantState(
            displayName: 'Marco',
            startedAt: DateTime(2026),
          ),
        ],
        isGroup: false,
      ),
      'typing…',
    );
    expect(
      conversationTypingLine(
        [
          TypingParticipantState(
            displayName: 'Marco',
            startedAt: DateTime(2026),
          ),
        ],
        isGroup: true,
      ),
      'Marco is typing…',
    );
    expect(
      conversationTypingLine(
        [
          TypingParticipantState(
            displayName: 'Marco',
            startedAt: DateTime(2026),
          ),
          TypingParticipantState(
            displayName: 'Priya',
            startedAt: DateTime(2026),
          ),
        ],
        isGroup: true,
      ),
      'Marco and Priya are typing…',
    );
  });
}
