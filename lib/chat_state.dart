import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_api.dart';
import 'chzzk_chat.dart';
import 'multiview_state.dart';

/// 채팅을 고정한 방송의 채널 ID. null이면 메인(소리 나는) 방송을 따라간다.
/// 채팅 탭을 오가도 유지되도록 채팅 접속과 따로 둔다.
final chatPinProvider = NotifierProvider<ChatPinNotifier, String?>(
  ChatPinNotifier.new,
);

class ChatPinNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pin(String? channelId) => state = channelId;
}

/// 채팅을 보여 줄 방송. 고정한 방송이 떠 있으면 그 방송, 아니면 메인 방송이다.
/// 고정한 방송을 닫으면 자연스럽게 메인을 따라가게 된다.
LiveInfo? chatTarget(MultiviewState state, String? pinned) {
  if (state.streams.isEmpty) return null;
  for (final live in state.streams) {
    if (live.channelId == pinned) return live;
  }
  return state.streams[state.mainIndex];
}

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

/// 고정한 방송 또는 메인(소리 나는) 방송의 채팅. 채팅 패널이 열려 있을 때만 접속한다.
final chatProvider = NotifierProvider.autoDispose<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

class ChatNotifier extends Notifier<ChatState> {
  static const maxMessages = 300;

  /// 채팅이 몰릴 때 메시지마다 화면을 다시 그리지 않도록, 잠시 모았다가 한 번에 반영한다.
  static const flushInterval = Duration(milliseconds: 100);
  final _pending = <ChatMessage>[];
  Timer? _flush;

  @override
  ChatState build() {
    // 보여 줄 방송이 바뀌거나, 같은 방송이라도 새로 켜서 채팅방이 바뀌면 다시 접속한다.
    final pinned = ref.watch(chatPinProvider);
    final target = ref.watch(
      multiviewProvider.select((s) {
        final live = chatTarget(s, pinned);
        if (live == null) return null;
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
    ref.onDispose(() {
      client.close();
      _flush?.cancel();
      _pending.clear();
    });
    // build 안에서 state를 바꾸지 않도록 접속은 다음 틱에 시작한다.
    scheduleMicrotask(client.start);
    return ChatState(channelName: target.name);
  }

  void _onMessages(List<ChatMessage> messages, {required bool replace}) {
    if (replace) {
      // 최근 채팅 목록은 접속 직후 한 번 오므로 바로 보여 준다.
      _flush?.cancel();
      _pending.clear();
      _setMessages(messages);
      return;
    }
    _pending.addAll(messages);
    _flush ??= Timer(flushInterval, () {
      _flush = null;
      final batch = [..._pending];
      _pending.clear();
      _setMessages([...state.messages, ...batch]);
    });
  }

  void _setMessages(List<ChatMessage> all) {
    state = state.copyWith(
      messages: all.length > maxMessages
          ? all.sublist(all.length - maxMessages)
          : all,
    );
  }
}
