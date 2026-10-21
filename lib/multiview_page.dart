import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'chzzk_api.dart';
import 'members_state.dart';
import 'multiview_state.dart';
import 'side_panel.dart';
import 'stream_tile.dart';
import 'tile_layout.dart';

class MultiviewPage extends ConsumerStatefulWidget {
  const MultiviewPage({super.key});

  @override
  ConsumerState<MultiviewPage> createState() => _MultiviewPageState();
}

class _MultiviewPageState extends ConsumerState<MultiviewPage> {
  bool _showPanel = true;

  /// 툴바와 패널을 숨기고 창을 전체 화면으로 만든 상태.
  bool _watchMode = false;

  @override
  void initState() {
    super.initState();
    // 타일을 클릭하면 포커스가 어디에도 없을 수 있어서, 화면 포커스가 아니라
    // 앱 전체 키 입력을 받는다.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }

    final focus = FocusManager.instance.primaryFocus;
    final editing =
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    final key = event.logicalKey;
    if (editing) {
      // 입력 중에는 단축키를 쓰지 않는다. Esc로 입력창에서 빠져나올 수 있다.
      if (key == LogicalKeyboardKey.escape) {
        focus!.unfocus();
        return true;
      }
      return false;
    }

    final multiview = ref.read(multiviewProvider.notifier);
    if (_digitIndex(key) case final index?) {
      final streams = ref.read(multiviewProvider).streams;
      if (index < streams.length) {
        multiview.selectAudio(streams[index].channelId);
      }
      return true;
    }
    switch (key) {
      case LogicalKeyboardKey.keyM:
        multiview.toggleMute();
      case LogicalKeyboardKey.keyG:
        final mode = ref.read(multiviewProvider).layoutMode;
        multiview.setLayoutMode(
          mode == LayoutMode.grid ? LayoutMode.focus : LayoutMode.grid,
        );
      case LogicalKeyboardKey.keyP:
        if (!_watchMode) setState(() => _showPanel = !_showPanel);
      case LogicalKeyboardKey.keyF:
        _setWatchMode(!_watchMode);
      case LogicalKeyboardKey.escape when _watchMode:
        _setWatchMode(false);
      default:
        return false;
    }
    return true;
  }

  static final _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static final _numpadKeys = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  /// 숫자 키 1~9를 타일 위치(0~8)로 바꾼다.
  static int? _digitIndex(LogicalKeyboardKey key) {
    final i = _digitKeys.indexOf(key);
    if (i >= 0) return i;
    final j = _numpadKeys.indexOf(key);
    return j >= 0 ? j : null;
  }

  Future<void> _setWatchMode(bool on) async {
    setState(() => _watchMode = on);
    await windowManager.setFullScreen(on);
    if (on && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('F 또는 Esc를 누르면 시청 모드에서 나갑니다'),
          duration: Duration(seconds: 2),
        ),
      );
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
          if (!_watchMode)
            _Toolbar(
              showPanel: _showPanel,
              onTogglePanel: () => setState(() => _showPanel = !_showPanel),
              onWatchMode: () => _setWatchMode(true),
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: streams.isEmpty
                      ? const Center(
                          child: Text('방송을 추가하거나 오른쪽 멤버 탭에서 멤버를 등록하세요'),
                        )
                      : _StreamGrid(streams: streams),
                ),
                if (_showPanel && !_watchMode) ...[
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 300, child: SidePanel()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 상단 툴바. 필요한 값만 따로 구독해서, 볼륨 슬라이더를 끌 때 타일 그리드까지
/// 다시 그리지 않게 한다.
class _Toolbar extends ConsumerStatefulWidget {
  const _Toolbar({
    required this.showPanel,
    required this.onTogglePanel,
    required this.onWatchMode,
  });

  final bool showPanel;
  final VoidCallback onTogglePanel;
  final VoidCallback onWatchMode;

  @override
  ConsumerState<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends ConsumerState<_Toolbar> {
  final _input = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _shortcutHelp = '''단축키
1~9: 해당 타일 소리 켜기
M: 음소거
G: 균등 분할 / 메인 + 서브 전환
P: 사이드 패널 열기 / 닫기
F: 시청 모드 (전체 화면)
Esc: 시청 모드 나가기 / 입력창에서 나가기''';

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
    final count = ref.watch(multiviewProvider.select((s) => s.streams.length));
    final muted = ref.watch(multiviewProvider.select((s) => s.muted));
    final volume = ref.watch(multiviewProvider.select((s) => s.volume));
    final layoutMode = ref.watch(multiviewProvider.select((s) => s.layoutMode));
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
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  tooltip: muted ? '음소거 해제 (M)' : '음소거 (M)',
                  onPressed: notifier.toggleMute,
                ),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: volume,
                    max: 100,
                    onChanged: notifier.setVolume,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<LayoutMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: LayoutMode.grid,
                      icon: Icon(Icons.grid_view),
                      tooltip: '균등 분할 (G)',
                    ),
                    ButtonSegment(
                      value: LayoutMode.focus,
                      icon: Icon(Icons.view_quilt),
                      tooltip: '메인 + 서브 (G)',
                    ),
                  ],
                  selected: {layoutMode},
                  onSelectionChanged: (s) => notifier.setLayoutMode(s.single),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: '시청 모드 (F)',
                  onPressed: widget.onWatchMode,
                ),
                IconButton(
                  icon: const Icon(Icons.people),
                  tooltip: widget.showPanel ? '사이드 패널 닫기 (P)' : '사이드 패널 열기 (P)',
                  isSelected: widget.showPanel,
                  onPressed: widget.onTogglePanel,
                ),
                const Tooltip(
                  message: _shortcutHelp,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.keyboard),
                  ),
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

/// 방송 수와 레이아웃 모드에 맞춰 화면을 나눈다.
///
/// 타일을 한 [Stack] 안에 두고 위치만 바꾸기 때문에, 방송을 추가하거나
/// 지우거나 메인을 바꿔도 남은 타일의 플레이어가 다시 만들어지지 않는다.
class _StreamGrid extends ConsumerWidget {
  const _StreamGrid({required this.streams});

  final List<LiveInfo> streams;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(
      multiviewProvider.select((s) => s.layoutMode == LayoutMode.focus),
    );
    final mainIndex = ref.watch(multiviewProvider.select((s) => s.mainIndex));

    return LayoutBuilder(
      builder: (context, constraints) {
        final rects = computeTileRects(
          constraints.biggest,
          streams.length,
          focus: focus,
          mainIndex: mainIndex,
        );
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              for (final (i, live) in streams.indexed)
                AnimatedPositioned.fromRect(
                  key: ValueKey(live.channelId),
                  rect: rects[i],
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: StreamTile(live: live, index: i),
                ),
            ],
          ),
        );
      },
    );
  }
}
