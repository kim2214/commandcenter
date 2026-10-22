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
  const StreamTile({super.key, required this.live, required this.index});

  final LiveInfo live;

  /// 타일 순서(0부터). 숫자 키 1~9로 고를 수 있도록 이름 앞에 번호를 붙인다.
  final int index;

  @override
  ConsumerState<StreamTile> createState() => _StreamTileState();
}

class _StreamTileState extends ConsumerState<StreamTile> {
  // 라이브는 되감지 않으므로 앞쪽 버퍼만 1080p 기준 10초 남짓으로 둔다.
  // (지난 구간 버퍼는 _configurePlayer에서 끈다.)
  final _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 16 * 1024 * 1024),
  );
  // 첫 화질은 initState에서 정해지므로, 처음 그릴 때 만들어지는 이 시점에는
  // _current가 이미 있다.
  late final _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      width: _outputSize(_current)?.width,
      height: _outputSize(_current)?.height,
    ),
  );
  late final Future<void> _ready = _configurePlayer();

  StreamVariant? _current;

  /// 사용자가 직접 고른 화질. null이면 타일 수에 따라 자동으로 고른다.
  StreamVariant? _manual;
  bool _hovered = false;
  bool _reconnecting = false;

  /// 방송이 끝났다. 잠깐 꺼졌다 다시 켜는 경우가 많아서 닫지 않고 드물게 다시 확인한다.
  bool _ended = false;

  late final StreamSubscription<bool> _completedSub;
  late final Timer _watchdog;

  /// 자동 화질 변경을 잠시 모으는 타이머. 타일 수가 연달아 바뀔 때 매번 다시 열지 않게 한다.
  Timer? _autoQualityTimer;
  static const _autoQualityDelay = Duration(milliseconds: 1500);
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
      (_, _) => _onAutoQualityChanged(),
      fireImmediately: true,
    );
    // 소리 타일이 아닌 타일은 볼륨을 0으로 두어 음소거한다. 오디오 트랙 자체는 끄지 않는다.
    // (mpv는 aid=no로 연 방송을 재생 도중 다시 켜지 못해, 싱글클릭으로 소리 타일을 바꿔도
    //  소리가 나지 않았다. 볼륨만 조절하면 이미 재생 중인 소리를 즉시 켜고 끌 수 있다.)
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
      if (Benchmark.enabled) {
        Timer(const Duration(seconds: 40), () async {
          final props = <String>[];
          for (final name in [
            'demuxer-lavf-o',
            'aid',
            'hwdec-current',
            'vd-lavc-threads',
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

  /// 처음 열 때는 바로 열고, 그 뒤의 자동 화질 변경은 잠시 모았다가 마지막 값만 적용한다.
  /// 방송이 여럿 한꺼번에 뜨거나 레이아웃을 연달아 바꿀 때 스트림을 거듭 다시 열지 않게 한다.
  void _onAutoQualityChanged() {
    if (_current == null || _manual != null) {
      _applyQuality();
      return;
    }
    _autoQualityTimer?.cancel();
    _autoQualityTimer = Timer(_autoQualityDelay, _applyQuality);
  }

  Future<void> _applyQuality() async {
    _autoQualityTimer?.cancel();
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
    await _applyDecoderOptions(target);
    if (_outputSize(target) case final size?) {
      await _controller.setSize(width: size.width, height: size.height);
    }
    if (!mounted) return;
    setState(() {});
    if (Benchmark.enabled) {
      debugPrint('bench: open ${widget.live.channelName} ${target.label}');
    }
    await _player.open(Media(target.url));
  }

  /// Linux용 영상 출력 크기. 다른 플랫폼은 null(영상 해상도를 그대로 따름)이다.
  ///
  /// media_kit_video 2.0.1의 Linux 소프트웨어 렌더링은 출력 크기가 정해져 있지 않으면
  /// 재생 시작 직후처럼 영상 정보가 아직 없을 때 초기화되지 않은 값을 읽다가 앱이 죽는다
  /// (`video_output_get_width`). 출력 크기를 화질 해상도로 고정하면 그 코드를 거치지 않는다.
  static ({int width, int height})? _outputSize(StreamVariant? variant) {
    if (!Platform.isLinux || variant == null) return null;
    return (width: (variant.height * 16 / 9).round(), height: variant.height);
  }

  /// 작은 화질의 디코딩 설정. 영상을 열기 전에 정해야 적용된다.
  Future<void> _applyDecoderOptions(StreamVariant variant) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final small = variant.height <= 480;

    // CPU 디코더는 기본으로 코어 수만큼 스레드를 띄우고 스레드마다 프레임 작업 공간을
    // 잡는다. 20코어 PC에서 14개를 띄우면 메모리가 약 650MB 더 들었다.
    // 480p 이하는 스레드 2개로 충분하다. (0은 자동)
    await platform.setProperty('vd-lavc-threads', small ? '2' : '0');

    // Linux에서는 플레이어마다 GPU 디코딩 공간(타일당 약 50MB)을 따로 잡는 비용이 커서,
    // CPU 부담이 거의 없는 480p 이하는 CPU로 해석한다. 다른 플랫폼은 측정 전이라 그대로 둔다.
    if (!Platform.isLinux) return;
    // 영상 출력이 만들어질 때 hwdec 기본값을 설정하므로, 그 뒤에 덮어쓴다.
    await _controller.platform.future;
    await platform.setProperty('hwdec', small ? 'no' : 'auto');
  }

  /// 새 주소를 받아 온다. 성공하면 [didUpdateWidget]에서 새 주소로 다시 연다.
  /// 실패하면 감시 타이머가 다음에 다시 시도한다. 멤버 방송이 끝났다면 멤버 동기화가 타일을 내린다.
  Future<void> _reconnect() async {
    if (_reconnecting || !mounted) return;
    // 새 주소도 바로 실패하는 경우 재연결이 연달아 반복되지 않게 간격을 둔다.
    // 방송이 끝난 뒤에는 다시 켜졌는지만 가끔 확인한다.
    final now = DateTime.now();
    final last = _lastReconnect;
    final gap = Duration(seconds: _ended ? 60 : 10);
    if (last != null && now.difference(last) < gap) return;
    _lastReconnect = now;
    setState(() => _reconnecting = true);
    try {
      await ref.read(multiviewProvider.notifier).refresh(_channelId);
      if (mounted) setState(() => _ended = false);
    } on StreamOfflineException {
      if (mounted) setState(() => _ended = true);
    } catch (_) {
      // 일시적인 오류는 다음 감시 주기에 다시 시도한다.
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
    _autoQualityTimer?.cancel();
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
    final solo = ref.watch(
      multiviewProvider.select((s) => s.soloChannelId == _channelId),
    );

    // 다른 타일의 손잡이를 끌어다 놓으면 이 자리로 옮긴다.
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != _channelId,
      onAcceptWithDetails: (details) => ref
          .read(liveSyncProvider.notifier)
          .moveTile(details.data, _channelId),
      builder: (context, candidates, _) => _buildTile(
        context,
        hasAudio: hasAudio,
        solo: solo,
        dropTarget: candidates.isNotEmpty,
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required bool hasAudio,
    required bool solo,
    required bool dropTarget,
  }) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 더블클릭을 기다리느라 소리 선택이 늦어지지 않게, 누르는 순간 처리한다.
        onTapDown: (_) =>
            ref.read(multiviewProvider.notifier).selectAudio(_channelId),
        onDoubleTap: () =>
            ref.read(multiviewProvider.notifier).toggleSolo(_channelId),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: NoVideoControls,
              fill: Colors.black,
            ),
            if (_ended)
              const Positioned.fill(child: _EndedOverlay())
            else if (_reconnecting)
              Center(child: _label('다시 연결 중…')),
            if (_hovered)
              Positioned(left: 6, right: 6, bottom: 6, child: _liveInfo()),
            if (solo)
              Positioned(
                right: 6,
                bottom: 6,
                child: _label('단독 보기 · 더블클릭 또는 Esc로 돌아가기'),
              ),
            // 소리가 나는 타일과 옮길 자리로 고른 타일은 테두리로 표시한다.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: dropTarget
                        ? colors.tertiary
                        : hasAudio
                        ? colors.primary
                        : Colors.white10,
                    width: dropTarget || hasAudio ? 3 : 1,
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
                  if (_hovered) ...[_dragHandle(), const SizedBox(width: 4)],
                  if (hasAudio)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.volume_up,
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                  Flexible(
                    child: _label(
                      widget.index < 9
                          ? '${widget.index + 1}  ${widget.live.channelName}'
                          : widget.live.channelName,
                    ),
                  ),
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

  /// 끌어서 다른 타일 위에 놓으면 그 자리로 옮겨진다. 클릭과 헷갈리지 않도록
  /// 타일 전체가 아니라 이 손잡이로만 끈다.
  Widget _dragHandle() {
    return Draggable<String>(
      data: _channelId,
      feedback: Material(
        color: Colors.transparent,
        child: _label('${widget.live.channelName} 옮기는 중'),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(message: '끌어서 순서 바꾸기', child: _label('⠿')),
      ),
    );
  }

  /// 방송 제목과 시청자 수. 멤버 방송이면 1분마다 갱신되는 방송 상태 값을 쓴다.
  Widget _liveInfo() {
    final status = ref.watch(
      liveSyncProvider.select((s) => s.statuses[_channelId]),
    );
    final title = status?.title ?? widget.live.title;
    final viewers = status?.viewers ?? widget.live.viewers;
    return Align(
      alignment: Alignment.bottomLeft,
      child: _label('$title · 시청자 $viewers명'),
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

/// 방송이 끝난 타일 위에 덮는 안내. 마지막 화면이 멈춰 있는 이유를 알려 준다.
class _EndedOverlay extends StatelessWidget {
  const _EndedOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tv_off, color: Colors.white70),
              SizedBox(height: 6),
              Text('방송이 종료됐어요', style: TextStyle(color: Colors.white)),
              Text(
                '다시 시작하면 자동으로 이어져요',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
