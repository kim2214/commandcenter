import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_api.dart';
import 'members_state.dart';
import 'multiview_state.dart';

/// 등록한 멤버 목록과 방송 상태를 보여 주는 사이드 패널.
class MembersPanel extends ConsumerStatefulWidget {
  const MembersPanel({super.key});

  @override
  ConsumerState<MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends ConsumerState<MembersPanel> {
  final _input = TextEditingController();
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ref.read(membersProvider.notifier).add(_input.text);
      _input.clear();
    } on ChzzkException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '등록 실패: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggle(Member member, {required bool shown}) async {
    final sync = ref.read(liveSyncProvider.notifier);
    if (shown) {
      sync.closeTile(member.channelId);
      return;
    }
    try {
      await sync.openTile(member.channelId);
    } on ChzzkException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${member.name}: ${e.message}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final sync = ref.watch(liveSyncProvider);
    final shown = ref.watch(
      multiviewProvider.select(
        (s) => {for (final live in s.streams) live.channelId},
      ),
    );
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text('멤버', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '방송 상태 새로고침',
                  onPressed: () => ref.read(liveSyncProvider.notifier).poll(),
                ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('방송 중인 멤버 자동으로 띄우기'),
            value: sync.autoSync,
            onChanged: ref.read(liveSyncProvider.notifier).setAutoSync,
          ),
          SwitchListTile(
            dense: true,
            title: const Text('멤버 방송 시작 알림'),
            value: sync.alerts,
            onChanged: ref.read(liveSyncProvider.notifier).setAlerts,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: '채널 ID 또는 채널 URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _adding ? null : _add(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  icon: _adding
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  tooltip: '멤버 등록',
                  onPressed: _adding ? null : _add,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: switch (members) {
              AsyncData(:final value) when value.isEmpty => const Center(
                child: Text('등록된 멤버가 없습니다'),
              ),
              AsyncData(:final value) => ReorderableListView(
                buildDefaultDragHandles: false,
                onReorderItem: ref.read(membersProvider.notifier).reorder,
                children: [
                  for (final (i, m) in value.indexed)
                    _MemberTile(
                      key: ValueKey(m.channelId),
                      index: i,
                      member: m,
                      status: sync.statuses[m.channelId],
                      shown: shown.contains(m.channelId),
                      onTap: () =>
                          _toggle(m, shown: shown.contains(m.channelId)),
                      onRemove: () => ref
                          .read(membersProvider.notifier)
                          .remove(m.channelId),
                    ),
                ],
              ),
              AsyncError(:final error) => Center(
                child: Text('멤버 목록을 불러오지 못했습니다\n$error'),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    super.key,
    required this.index,
    required this.member,
    required this.status,
    required this.shown,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final Member member;
  final LiveStatus? status;
  final bool shown;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLive = status?.isLive ?? false;
    final imageUrl = member.imageUrl;

    return ListTile(
      dense: true,
      selected: shown,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Icon(Icons.drag_indicator, size: 18),
            ),
          ),
          const SizedBox(width: 4),
          Badge(
            isLabelVisible: isLive,
            backgroundColor: Colors.red,
            smallSize: 10,
            child: CircleAvatar(
              radius: 18,
              backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl),
              child: imageUrl == null
                  ? Text(member.name.characters.firstOrNull ?? '?')
                  : null,
            ),
          ),
        ],
      ),
      title: Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        switch (status) {
          null => '확인 중…',
          LiveStatus(isLive: false) => '오프라인',
          final s => '${s.title} · ${s.viewers}명',
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shown) Icon(Icons.tv, size: 18, color: colors.primary),
          PopupMenuButton<void>(
            tooltip: '더 보기',
            icon: const Icon(Icons.more_vert, size: 18),
            itemBuilder: (_) => [
              PopupMenuItem(onTap: onRemove, child: const Text('멤버 삭제')),
            ],
          ),
        ],
      ),
      // 오프라인 멤버는 띄울 수 없으니 누를 수 없게 한다. 메뉴는 그대로 쓸 수 있다.
      onTap: isLive || shown ? onTap : null,
    );
  }
}
