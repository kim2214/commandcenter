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

class MultiviewState {
  const MultiviewState({
    this.streams = const [],
    this.audioChannelId,
    this.volume = 100,
    this.muted = false,
  });

  final List<LiveInfo> streams;

  /// 소리가 나는 타일의 채널 ID. 나머지 타일은 모두 음소거된다.
  final String? audioChannelId;
  final double volume;
  final bool muted;

  /// 타일 수가 늘어날수록 각 타일이 작아지므로 자동 화질 상한을 낮춘다.
  int get autoMaxHeight => switch (streams.length) {
    <= 1 => 1080,
    <= 4 => 720,
    <= 9 => 480,
    _ => 360,
  };

  MultiviewState copyWith({
    List<LiveInfo>? streams,
    String? Function()? audioChannelId,
    double? volume,
    bool? muted,
  }) {
    return MultiviewState(
      streams: streams ?? this.streams,
      audioChannelId: audioChannelId != null
          ? audioChannelId()
          : this.audioChannelId,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
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

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
  }
}
