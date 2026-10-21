import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_chat.dart';
import 'multiview_state.dart';

class ChatState {
  const ChatState({
    this.channelName,
    this.available = true,
    this.status = ChatStatus.connecting,
    this.messages = const [],
  });

  /// 채팅을 보여 주는 방송의 채널 이름. 띄운 방송이 없으면 null이다.
  final String? channelName;

  /// 채팅이 꺼진 방송이면 false다.
  final bool available;
  final ChatStatus status;

  /// 오래된 것부터 최신 순.
  final List<ChatMessage> messages;

  ChatState copyWith({ChatStatus? status, List<ChatMessage>? messages}) {
    return ChatState(
      channelName: channelName,
      available: available,
      status: status ?? this.status,
      messages: messages ?? this.messages,
    );
  }
}

/// 메인(소리 나는) 방송의 채팅. 채팅 패널이 열려 있을 때만 접속한다.
final chatProvider = NotifierProvider.autoDispose<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

class ChatNotifier extends Notifier<ChatState> {
  static const maxMessages = 300;

  @override
  ChatState build() {
    // 메인 방송이 바뀌거나, 같은 방송이라도 새로 켜서 채팅방이 바뀌면 다시 접속한다.
    final target = ref.watch(
      multiviewProvider.select((s) {
        if (s.streams.isEmpty) return null;
        final live = s.streams[s.mainIndex];
        return (name: live.channelName, chatChannelId: live.chatChannelId);
      }),
    );
    if (target == null) return const ChatState();

    final chatChannelId = target.chatChannelId;
    if (chatChannelId == null) {
      return ChatState(channelName: target.name, available: false);
    }

    final client = ChzzkChatClient(
      api: ref.read(chzzkApiProvider),
      chatChannelId: chatChannelId,
      onMessages: _onMessages,
      onStatus: (status) => state = state.copyWith(status: status),
    );
    ref.onDispose(client.close);
    // build 안에서 state를 바꾸지 않도록 접속은 다음 틱에 시작한다.
    scheduleMicrotask(client.start);
    return ChatState(channelName: target.name);
  }

  void _onMessages(List<ChatMessage> messages, {required bool replace}) {
    final all = replace ? messages : [...state.messages, ...messages];
    state = state.copyWith(
      messages: all.length > maxMessages
          ? all.sublist(all.length - maxMessages)
          : all,
    );
  }
}
