import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_state.dart';
import 'chzzk_chat.dart';

/// 메인(소리 나는) 방송의 채팅을 보여 주는 패널.
class ChatPanel extends ConsumerWidget {
  const ChatPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chat.channelName ?? '채팅',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (chat.channelName != null && chat.available)
                  _StatusDot(status: chat.status),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (chat) {
              ChatState(channelName: null) => const _Hint(
                '방송을 추가하면 메인 방송의 채팅이 보여요',
              ),
              ChatState(available: false) => const _Hint('이 방송은 채팅이 꺼져 있어요'),
              ChatState(messages: []) => const _Hint('채팅을 기다리는 중…'),
              _ => ListView.builder(
                // 최신 메시지가 아래에 붙고, 맨 아래에 있으면 계속 따라 내려간다.
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: chat.messages.length,
                itemBuilder: (context, i) => _MessageTile(
                  message: chat.messages[chat.messages.length - 1 - i],
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final ChatStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ChatStatus.connected => (Colors.green, '연결됨'),
      ChatStatus.connecting => (Colors.amber, '연결 중'),
      ChatStatus.reconnecting => (Colors.red, '다시 연결 중'),
    };
    return Tooltip(
      message: label,
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  static const _nicknameColors = [
    Color(0xFF64B5F6),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFFFB74D),
    Color(0xFFF06292),
    Color(0xFFAED581),
    Color(0xFF9575CD),
    Color(0xFF4FC3F7),
  ];

  Color _nicknameColor(String nickname) => switch (message.role) {
    ChatRole.streamer => const Color(0xFFFF7043),
    ChatRole.manager => const Color(0xFF66BB6A),
    ChatRole.viewer =>
      _nicknameColors[nickname.hashCode.abs() % _nicknameColors.length],
  };

  @override
  Widget build(BuildContext context) {
    final nickname = message.nickname ?? '익명';
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$nickname  ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _nicknameColor(nickname),
            ),
          ),
          for (final segment in message.segments)
            switch (segment) {
              TextSegment(:final text) => TextSpan(text: text),
              EmojiSegment(:final name, :final url) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image.network(
                  url,
                  height: 22,
                  errorBuilder: (_, _, _) => Text('{:$name:}'),
                ),
              ),
            },
        ],
      ),
      style: const TextStyle(fontSize: 13, height: 1.4),
    );

    if (!message.isDonation) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: text,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.payAmount > 0 ? '후원 ${message.payAmount}원' : '후원',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: colors.onTertiaryContainer,
            ),
          ),
          text,
        ],
      ),
    );
  }
}
