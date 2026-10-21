import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'chzzk_api.dart';
import 'multiview_state.dart';

/// 방송 하나를 재생하는 타일. 타일마다 자기 [Player]를 가진다.
class StreamTile extends ConsumerStatefulWidget {
  const StreamTile({super.key, required this.live});

  final LiveInfo live;

  @override
  ConsumerState<StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends ConsumerState<StreamTile> {
  final _player = Player();
  late final _controller = VideoController(_player);
  late final Future<void> _ready = _configurePlayer();

  StreamVariant? _current;

  /// 사용자가 직접 고른 화질. null이면 타일 수에 따라 자동으로 고른다.
  StreamVariant? _manual;
  bool _hovered = false;

  String get _channelId => widget.live.channelId;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      multiviewProvider.select((s) => s.autoMaxHeight),
      (_, _) => _applyQuality(),
      fireImmediately: true,
    );
    ref.listenManual(
      multiviewProvider.select(
        (s) => s.audioChannelId == _channelId && !s.muted ? s.volume : 0.0,
      ),
      (_, volume) => _player.setVolume(volume),
      fireImmediately: true,
    );
  }

  Future<void> _configurePlayer() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // 치지직 HLS 세그먼트 확장자가 .m4v라서 ffmpeg 기본 검사에 걸린다.
      await platform.setProperty('demuxer-lavf-o', 'extension_picky=0');
    }
  }

  Future<void> _applyQuality() async {
    final variants = widget.live.variants;
    final maxHeight = ref.read(multiviewProvider).autoMaxHeight;
    final target =
        _manual ??
        variants.firstWhere(
          (v) => v.height <= maxHeight,
          orElse: () => variants.last,
        );
    if (target == _current) return;

    setState(() => _current = target);
    await _ready;
    await _player.open(Media(target.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = ref.watch(
      multiviewProvider.select((s) => s.audioChannelId == _channelId),
    );
    final colors = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            ref.read(multiviewProvider.notifier).selectAudio(_channelId),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fill: Colors.black,
            ),
            // 소리가 나는 타일은 테두리로 표시한다.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasAudio ? colors.primary : Colors.white10,
                    width: hasAudio ? 3 : 1,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              right: 6,
              child: Row(
                children: [
                  if (hasAudio)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.volume_up,
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                  Flexible(child: _label(widget.live.channelName)),
                  const Spacer(),
                  if (_hovered) ...[
                    _qualityMenu(),
                    const SizedBox(width: 4),
                    _iconButton(
                      icon: Icons.close,
                      tooltip: '닫기',
                      onPressed: () => ref
                          .read(multiviewProvider.notifier)
                          .remove(_channelId),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }

  Widget _qualityMenu() {
    // null 값은 메뉴 취소로 처리되므로 자동은 높이 0으로 나타낸다.
    return PopupMenuButton<int>(
      tooltip: '화질',
      onSelected: (height) {
        _manual = height == 0
            ? null
            : widget.live.variants.firstWhere((v) => v.height == height);
        _applyQuality();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 0,
          checked: _manual == null,
          child: const Text('자동'),
        ),
        for (final v in widget.live.variants)
          CheckedPopupMenuItem(
            value: v.height,
            checked: _manual == v,
            child: Text(v.label),
          ),
      ],
      child: _label(
        _manual == null ? '자동 (${_current?.label ?? '-'})' : _current!.label,
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
