import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'benchmark.dart';
import 'chzzk_api.dart';
import 'members_state.dart';
import 'multiview_state.dart';

/// 방송 하나를 재생하는 타일. 타일마다 자기 [Player]를 가진다.
class StreamTile extends ConsumerStatefulWidget {
  const StreamTile({super.key, required this.live});

  final LiveInfo live;

  @override
  ConsumerState<StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends ConsumerState<StreamTile> {
  // 라이브는 되감지 않으므로 앞쪽 버퍼만 1080p 기준 10초 남짓으로 둔다.
  // (지난 구간 버퍼는 _configurePlayer에서 끈다.)
  final _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  late final _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(hwdec: Benchmark.hwdec),
  );
  late final Future<void> _ready = _configurePlayer();

  StreamVariant? _current;

  /// 사용자가 직접 고른 화질. null이면 타일 수에 따라 자동으로 고른다.
  StreamVariant? _manual;
  bool _hovered = false;
  bool _reconnecting = false;

  late final StreamSubscription<bool> _completedSub;
  late final Timer _watchdog;
  Duration _lastPosition = Duration.zero;
  int _stalledChecks = 0;
  DateTime? _lastReconnect;

  String get _channelId => widget.live.channelId;

  @override
  void initState() {
    super.initState();
    // 라이브는 정상이라면 끝나지 않으므로, 재생이 끝나면 끊긴 것으로 보고 재연결한다.
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _reconnect();
    });
    // 토큰 만료나 네트워크 문제로 재생 위치가 30초 동안 멈추면 재연결한다.
    _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
      final position = _player.state.position;
      if (position == _lastPosition && ++_stalledChecks >= 2) {
        _stalledChecks = 0;
        _reconnect();
      } else if (position != _lastPosition) {
        _stalledChecks = 0;
      }
      _lastPosition = position;
    });
    ref.listenManual(
      multiviewProvider.select((s) => s.maxHeightFor(_channelId)),
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
    // 소리 타일이 아니면 오디오 트랙을 아예 꺼서 해석과 오디오 출력을 하지 않는다.
    ref.listenManual(
      multiviewProvider.select((s) => s.audioChannelId == _channelId),
      (_, hasAudio) => _setAudioEnabled(hasAudio),
      fireImmediately: true,
    );
  }

  Future<void> _configurePlayer() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // 치지직 HLS 세그먼트 확장자가 .m4v라서 ffmpeg 기본 검사에 걸린다.
      // media_kit 기본 옵션(조각 다운로드 재시도 등)은 그대로 두고 이 검사만 덧붙인다.
      // 문자열로 읽어 다시 쓰면 `protocol_whitelist=[...]`의 대괄호가 사라져
      // https가 막히므로, 목록에 항목만 추가하는 명령을 쓴다.
      await platform.command([
        'change-list',
        'demuxer-lavf-o',
        'append',
        'extension_picky=0',
      ]);
      await platform.setProperty('demuxer-max-back-bytes', '0');
      for (final MapEntry(:key, :value) in Benchmark.mpvOverrides.entries) {
        await platform.setProperty(key, value);
      }
      if (Benchmark.enabled) {
        Timer(const Duration(seconds: 40), () async {
          final props = <String>[];
          for (final name in [
            'demuxer-lavf-o',
            'aid',
            'hwdec-current',
            'width',
            'height',
            'demuxer-cache-duration',
          ]) {
            props.add('$name=${await platform.getProperty(name)}');
          }
          debugPrint(
            'bench: tile ${widget.live.channelName} ${props.join(' ')}',
          );
        });
      }
    }
  }

  Future<void> _applyQuality() async {
    final variants = widget.live.variants;
    final maxHeight = ref.read(multiviewProvider).maxHeightFor(_channelId);
    final target =
        _manual ??
        variants.firstWhere(
          (v) => v.height <= maxHeight,
          orElse: () => variants.last,
        );
    if (target == _current) return;

    _current = target;
    await _ready;
    await _applyHardwareDecoding(target);
    if (!mounted) return;
    setState(() {});
    await _player.open(Media(target.url));
  }

  Future<void> _setAudioEnabled(bool enabled) async {
    await _ready;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('aid', enabled ? 'auto' : 'no');
    }
  }

  /// Linux에서는 플레이어마다 GPU 디코딩 공간(타일당 약 50MB)을 따로 잡는 비용이 커서,
  /// CPU 부담이 거의 없는 480p 이하는 CPU로 해석한다. 다른 플랫폼은 측정 전이라 그대로 둔다.
  Future<void> _applyHardwareDecoding(StreamVariant variant) async {
    if (!Platform.isLinux || Benchmark.hwdec != null) return;
    // 영상 출력이 만들어질 때 hwdec 기본값을 설정하므로, 그 뒤에 덮어쓴다.
    await _controller.platform.future;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('hwdec', variant.height > 480 ? 'auto' : 'no');
    }
  }

  /// 새 주소를 받아 온다. 성공하면 [didUpdateWidget]에서 새 주소로 다시 연다.
  /// 실패하면 감시 타이머가 다음에 다시 시도하고, 방송이 끝났다면 멤버 동기화가 타일을 내린다.
  Future<void> _reconnect() async {
    if (_reconnecting || !mounted) return;
    // 새 주소도 바로 실패하는 경우 재연결이 연달아 반복되지 않게 간격을 둔다.
    final now = DateTime.now();
    final last = _lastReconnect;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastReconnect = now;
    setState(() => _reconnecting = true);
    try {
      await ref.read(multiviewProvider.notifier).refresh(_channelId);
    } catch (_) {
      // 다음 감시 주기에 다시 시도한다.
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  void didUpdateWidget(StreamTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live != widget.live) {
      final manual = _manual;
      _manual = manual == null
          ? null
          : widget.live.variants
                .where((v) => v.height == manual.height)
                .firstOrNull;
      _current = null;
      _applyQuality();
    }
  }

  @override
  void dispose() {
    _watchdog.cancel();
    _completedSub.cancel();
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
            if (_reconnecting) Center(child: _label('다시 연결 중…')),
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
                          .read(liveSyncProvider.notifier)
                          .closeTile(_channelId),
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
