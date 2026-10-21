import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_api.dart';
import 'members_panel.dart';
import 'members_state.dart';
import 'multiview_state.dart';
import 'stream_tile.dart';

class MultiviewPage extends ConsumerStatefulWidget {
  const MultiviewPage({super.key});

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  final _input = TextEditingController();
  bool _loading = false;
  bool _showMembers = true;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(multiviewProvider.notifier).add(_input.text);
      _input.clear();
    } on ChzzkException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '불러오기 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final streams = ref.watch(multiviewProvider.select((s) => s.streams));
    // 패널을 닫아 둬도 방송 상태 확인은 계속 돌도록 여기서 붙잡아 둔다.
    ref.listen(liveSyncProvider, (_, _) {});

    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(context, streams.length),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: streams.isEmpty
                      ? const Center(child: Text('방송을 추가하거나 오른쪽에서 멤버를 등록하세요'))
                      : _StreamGrid(streams: streams),
                ),
                if (_showMembers) ...[
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 300, child: MembersPanel()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, int count) {
    final state = ref.watch(multiviewProvider);
    final notifier = ref.read(multiviewProvider.notifier);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      labelText: '채널 ID 또는 라이브 URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _loading ? null : _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _add,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('추가'),
                ),
                const SizedBox(width: 16),
                Text('$count / ${MultiviewNotifier.maxStreams}'),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(state.muted ? Icons.volume_off : Icons.volume_up),
                  tooltip: state.muted ? '음소거 해제' : '음소거',
                  onPressed: notifier.toggleMute,
                ),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: state.volume,
                    max: 100,
                    onChanged: notifier.setVolume,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.people),
                  tooltip: _showMembers ? '멤버 패널 닫기' : '멤버 패널 열기',
                  isSelected: _showMembers,
                  onPressed: () => setState(() => _showMembers = !_showMembers),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 방송 수에 맞춰 화면을 격자로 나눈다.
///
/// 타일을 한 [Stack] 안에 두고 위치만 바꾸기 때문에, 방송을 추가하거나
/// 지워도 남은 타일의 플레이어가 다시 만들어지지 않는다.
class _StreamGrid extends StatelessWidget {
  const _StreamGrid({required this.streams});

  final List<LiveInfo> streams;

  @override
  Widget build(BuildContext context) {
    final count = streams.length;
    final columns = sqrt(count).ceil();
    final rows = (count / columns).ceil();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / columns;
        final height = constraints.maxHeight / rows;
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              for (final (i, live) in streams.indexed)
                Positioned(
                  key: ValueKey(live.channelId),
                  left: (i % columns) * width,
                  top: (i ~/ columns) * height,
                  width: width,
                  height: height,
                  child: StreamTile(live: live),
                ),
            ],
          ),
        );
      },
    );
  }
}
