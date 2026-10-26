import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_state.dart';
import 'chzzk_chat.dart';
import 'format.dart';
import 'multiview_state.dart';

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
                Expanded(child: _ChatTargetMenu(channelName: chat.channelName)),
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
              // 다른 방송으로 바뀌면 스크롤 상태도 새로 시작한다.
              _ => _ChatList(
                key: ValueKey(chat.channelName),
                messages: chat.messages,
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// 채팅 목록. 맨 아래에 있으면 새 채팅을 따라 내려가고, 위로 올려서 지난 채팅을
/// 보는 동안에는 목록을 고정해 화면이 밀리지 않게 한다.
class _ChatList extends StatefulWidget {
  const _ChatList({super.key, required this.messages});

  /// 오래된 것부터 최신 순.
  final List<ChatMessage> messages;

  @override
  State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
  final _scroll = ScrollController();

  /// 위로 스크롤한 동안 보여 줄 목록. null이면 실시간으로 따라간다.
  List<ChatMessage>? _frozen;

  /// 목록을 뒤집어 그리므로 offset 0이 맨 아래(최신)다.
  static const _bottomThreshold = 24.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final atBottom = _scroll.offset <= _bottomThreshold;
    if (!atBottom && _frozen == null) {
      setState(() => _frozen = widget.messages);
    } else if (atBottom && _frozen != null) {
      setState(() => _frozen = null);
    }
  }

  /// 고정한 뒤 새로 온 채팅 수. 오래돼서 목록에서 밀려났으면 전체 개수로 센다.
  int get _newCount {
    final frozen = _frozen;
    if (frozen == null || frozen.isEmpty) return 0;
    final i = widget.messages.lastIndexOf(frozen.last);
    return i < 0 ? widget.messages.length : widget.messages.length - 1 - i;
  }

  void _jumpToLatest() {
    setState(() => _frozen = null);
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _frozen ?? widget.messages;
    final newCount = _newCount;

    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: messages.length,
          itemBuilder: (context, i) =>
              _MessageTile(message: messages[messages.length - 1 - i]),
        ),
        if (_frozen != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _jumpToLatest,
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: Text(newCount > 0 ? '새 채팅 $newCount개' : '최신 채팅으로'),
              ),
            ),
          ),
      ],
    );
  }
}

/// 어느 방송의 채팅을 볼지 고르는 메뉴. 기본은 메인(소리 나는) 방송을 따라간다.
class _ChatTargetMenu extends ConsumerWidget {
  const _ChatTargetMenu({required this.channelName});

  /// 지금 채팅을 보여 주는 방송의 이름.
  final String? channelName;

  // 메뉴 값이 null이면 메뉴 닫기로 처리되므로, "메인 따라가기"는 빈 문자열로 나타낸다.
  static const _followMain = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = Theme.of(context).textTheme.titleMedium;
    final name = channelName;
    if (name == null) return Text('채팅', style: style);

    final streams = ref.watch(multiviewProvider.select((s) => s.streams));
    final pinned = ref.watch(chatPinProvider);
    final isPinned = streams.any((s) => s.channelId == pinned);

    return PopupMenuButton<String>(
      tooltip: '채팅을 볼 방송 고르기',
      position: PopupMenuPosition.under,
      onSelected: (id) =>
          ref.read(chatPinProvider.notifier).pin(id == _followMain ? null : id),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: _followMain,
          checked: !isPinned,
          child: const Text('메인 방송 따라가기'),
        ),
        const PopupMenuDivider(),
        for (final live in streams)
          CheckedPopupMenuItem(
            value: live.channelId,
            checked: isPinned && live.channelId == pinned,
            child: Text(live.channelName),
          ),
      ],
      child: Row(
        children: [
          Icon(isPinned ? Icons.push_pin : Icons.volume_up, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const Icon(Icons.arrow_drop_down),
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
                  // 표시 크기에 맞춰 줄여서 해석한다 (고해상도 화면용으로 2배).
                  cacheHeight: 44,
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
            message.payAmount > 0
                ? '후원 ${formatCount(message.payAmount)}원'
                : '후원',
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
