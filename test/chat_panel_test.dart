import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:command_center/chat_panel.dart';
import 'package:command_center/chat_state.dart';
import 'package:command_center/chzzk_chat.dart';
import 'package:command_center/settings.dart';

/// 채팅 서버에 접속하지 않고 테스트에서 메시지를 직접 넣는 가짜 상태.
class _FakeChat extends ChatNotifier {
  @override
  ChatState build() => ChatState(
    channelName: '테스트',
    status: ChatStatus.connected,
    messages: _messages(0, 60),
  );

  void push(int from, int count) {
    state = state.copyWith(
      messages: [...state.messages, ..._messages(from, count)],
    );
  }
}

List<ChatMessage> _messages(int from, int count) => [
  for (var i = from; i < from + count; i++)
    ChatMessage(nickname: 'user$i', text: 'message $i'),
];

void main() {
  late _FakeChat chat;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith(() => chat = _FakeChat()),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: ChatPanel())),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('follows new messages while at the bottom', (tester) async {
    await pumpPanel(tester);
    chat.push(60, 1);
    await tester.pump();
    expect(find.textContaining('message 60'), findsOneWidget);
    expect(find.textContaining('새 채팅'), findsNothing);
  });

  testWidgets('holds the list while scrolled up and counts new messages', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('최신 채팅으로'), findsOneWidget);

    chat.push(60, 3);
    await tester.pump();
    // 고정된 동안에는 새 메시지가 목록에 들어오지 않는다.
    expect(find.textContaining('message 62'), findsNothing);
    expect(find.text('새 채팅 3개'), findsOneWidget);

    await tester.tap(find.text('새 채팅 3개'));
    await tester.pumpAndSettle();
    expect(find.textContaining('message 62'), findsOneWidget);
    expect(find.textContaining('새 채팅'), findsNothing);
  });
}
