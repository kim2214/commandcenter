import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'chzzk_api.dart';

/// 1분할 시제품: 채널 하나를 불러와 media_kit으로 재생한다.
class LivePlayerPage extends StatefulWidget {
  const LivePlayerPage({super.key});

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  final _api = ChzzkApi();
  final _player = Player();
  late final _controller = VideoController(_player);
  final _input = TextEditingController();

  LiveInfo? _live;
  StreamVariant? _variant;
  String? _error;
  bool _loading = false;
  bool _muted = false;
  double _volume = 100;

  @override
  void initState() {
    super.initState();
    _configurePlayer();
  }

  Future<void> _configurePlayer() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // 치지직 HLS 세그먼트 확장자가 .m4v라서 ffmpeg 기본 검사에 걸린다.
      await platform.setProperty('demuxer-lavf-o', 'extension_picky=0');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _api.close();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final channelId = ChzzkApi.parseChannelId(_input.text);
    if (channelId == null) {
      setState(() => _error = '채널 ID 또는 치지직 라이브 URL을 입력하세요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final live = await _api.fetchLive(channelId);
      // 멀티뷰에서 타일 하나가 작아지는 걸 감안해 기본 화질은 480p로 둔다.
      final variant = live.variants.firstWhere(
        (v) => v.height <= 480,
        orElse: () => live.variants.last,
      );
      setState(() => _live = live);
      await _play(variant);
    } on ChzzkException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '불러오기 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(StreamVariant variant) async {
    setState(() => _variant = variant);
    await _player.open(Media(variant.url));
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _player.setVolume(_muted ? 0 : _volume);
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    return Scaffold(
      appBar: AppBar(title: const Text('Chzzk Multiviewer')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      labelText: '채널 ID 또는 라이브 URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _load,
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('불러오기'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: Video(controller: _controller, controls: NoVideoControls),
            ),
          ),
          if (live != null) _buildControls(live),
        ],
      ),
    );
  }

  Widget _buildControls(LiveInfo live) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${live.channelName} · 시청자 ${live.viewers}명'),
              ],
            ),
          ),
          DropdownButton<StreamVariant>(
            value: _variant,
            items: [
              for (final v in live.variants)
                DropdownMenuItem(value: v, child: Text(v.label)),
            ],
            onChanged: (v) {
              if (v != null && v != _variant) _play(v);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            tooltip: _muted ? '음소거 해제' : '음소거',
            onPressed: _toggleMute,
          ),
          SizedBox(
            width: 140,
            child: Slider(
              value: _volume,
              max: 100,
              onChanged: (v) {
                setState(() {
                  _volume = v;
                  _muted = false;
                });
                _player.setVolume(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
