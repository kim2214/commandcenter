import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_api.dart';

final chzzkApiProvider = Provider<ChzzkApi>((ref) {
  final api = ChzzkApi();
  ref.onDispose(api.close);
  return api;
});

final multiviewProvider = NotifierProvider<MultiviewNotifier, MultiviewState>(
  MultiviewNotifier.new,
);

enum LayoutMode {
  /// 모든 방송을 같은 크기로 나눈다.
  grid,

  /// 소리가 나는 방송을 크게, 나머지를 작게 둔다.
  focus,
}

class MultiviewState {
  const MultiviewState({
    this.streams = const [],
    this.audioChannelId,
    this.volume = 100,
    this.muted = false,
    this.layoutMode = LayoutMode.grid,
  });

  final List<LiveInfo> streams;

  /// 소리가 나는 타일의 채널 ID. 나머지 타일은 모두 음소거된다.
  /// 메인 + 서브 레이아웃에서는 이 방송이 메인이 된다.
  final String? audioChannelId;
  final double volume;
  final bool muted;
  final LayoutMode layoutMode;

  /// 메인 + 서브 레이아웃에서 크게 보일 방송의 위치.
  int get mainIndex {
    final i = streams.indexWhere((s) => s.channelId == audioChannelId);
    return i < 0 ? 0 : i;
  }

  /// 타일이 작을수록 높은 화질이 의미가 없으므로 자동 화질 상한을 낮춘다.
  int maxHeightFor(String channelId) {
    if (layoutMode == LayoutMode.focus && streams.length > 1) {
      if (streams[mainIndex].channelId == channelId) return 1080;
      return streams.length <= 4 ? 480 : 360;
    }
    return switch (streams.length) {
      <= 1 => 1080,
      <= 4 => 720,
      <= 9 => 480,
      _ => 360,
    };
  }

  MultiviewState copyWith({
    List<LiveInfo>? streams,
    String? Function()? audioChannelId,
    double? volume,
    bool? muted,
    LayoutMode? layoutMode,
  }) {
    return MultiviewState(
      streams: streams ?? this.streams,
      audioChannelId: audioChannelId != null
          ? audioChannelId()
          : this.audioChannelId,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }
}

class MultiviewNotifier extends Notifier<MultiviewState> {
  static const maxStreams = 16;

  @override
  MultiviewState build() => const MultiviewState();

  /// 입력한 채널을 불러와 타일로 추가한다. 실패하면 [ChzzkException]을 던진다.
  Future<void> add(String input) async {
    final channelId = ChzzkApi.parseChannelId(input);
    if (channelId == null) {
      throw ChzzkException('채널 ID 또는 치지직 라이브 URL을 입력하세요');
    }
    if (state.streams.any((s) => s.channelId == channelId)) {
      throw ChzzkException('이미 추가된 방송입니다');
    }
    if (state.streams.length >= maxStreams) {
      throw ChzzkException('최대 $maxStreams개까지 추가할 수 있습니다');
    }

    final live = await ref.read(chzzkApiProvider).fetchLive(channelId);
    // 불러오는 동안 같은 채널이 먼저 추가됐을 수 있다.
    if (state.streams.any((s) => s.channelId == channelId)) return;

    state = state.copyWith(
      streams: [...state.streams, live],
      // 첫 방송은 바로 소리가 나도록 선택한다.
      audioChannelId: state.audioChannelId == null ? () => channelId : null,
    );
  }

  void remove(String channelId) {
    final streams = [
      for (final s in state.streams)
        if (s.channelId != channelId) s,
    ];
    final audioId = state.audioChannelId == channelId
        ? (streams.isEmpty ? null : streams.first.channelId)
        : state.audioChannelId;
    state = state.copyWith(streams: streams, audioChannelId: () => audioId);
  }

  /// 방송 주소를 다시 받아 타일을 갱신한다. 주소의 인증 토큰이 만료됐거나
  /// 방송이 잠깐 끊겼다 다시 켜졌을 때 재연결에 쓴다.
  Future<void> refresh(String channelId) async {
    final live = await ref.read(chzzkApiProvider).fetchLive(channelId);
    state = state.copyWith(
      streams: [
        for (final s in state.streams) s.channelId == channelId ? live : s,
      ],
    );
  }

  void selectAudio(String channelId) {
    state = state.copyWith(audioChannelId: () => channelId, muted: false);
  }

  void setVolume(double volume) {
    state = state.copyWith(volume: volume, muted: false);
  }

  void setLayoutMode(LayoutMode mode) {
    state = state.copyWith(layoutMode: mode);
  }

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
  }
}
