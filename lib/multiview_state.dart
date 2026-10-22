import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chzzk_api.dart';
import 'settings.dart';
import 'tile_layout.dart';

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
    this.layoutMode = LayoutMode.grid,
    this.soloChannelId,
  });

  final List<LiveInfo> streams;

  /// 소리가 나는 타일의 채널 ID. 나머지 타일은 모두 음소거된다.
  /// 메인 + 서브 레이아웃에서는 이 방송이 메인이 된다.
  final String? audioChannelId;
  final double volume;
  final bool muted;
  final LayoutMode layoutMode;

  /// 단독 보기 중인 방송. 이 방송만 화면 가득 보이고 나머지는 숨긴 채 계속 재생한다.
  final String? soloChannelId;

  /// 단독 보기 중인 방송의 위치. 단독 보기가 아니면 null.
  int? get soloIndex {
    final i = streams.indexWhere((s) => s.channelId == soloChannelId);
    return i < 0 ? null : i;
  }

  /// 메인 + 서브 레이아웃에서 크게 보일 방송의 위치.
  int get mainIndex {
    final i = streams.indexWhere((s) => s.channelId == audioChannelId);
    return i < 0 ? 0 : i;
  }

  /// 타일이 작을수록 높은 화질이 의미가 없으므로 자동 화질 상한을 낮춘다.
  int maxHeightFor(String channelId) {
    // 단독 보기는 화면 전체를 쓴다. 숨긴 방송은 돌아왔을 때 다시 버퍼링하지 않도록
    // 화질을 그대로 둔다.
    if (soloChannelId == channelId) return 1080;
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
    String? Function()? soloChannelId,
  }) {
    return MultiviewState(
      streams: streams ?? this.streams,
      audioChannelId: audioChannelId != null
          ? audioChannelId()
          : this.audioChannelId,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      layoutMode: layoutMode ?? this.layoutMode,
      soloChannelId: soloChannelId != null
          ? soloChannelId()
          : this.soloChannelId,
    );
  }
}

class MultiviewNotifier extends Notifier<MultiviewState> {
  static const maxStreams = 16;

  Timer? _volumeSave;

  /// 아직 저장하지 않은 볼륨. 닫힐 때는 [state]를 읽을 수 없어서 따로 들고 있는다.
  double? _pendingVolume;

  @override
  MultiviewState build() {
    final settings = ref.read(settingsStoreProvider);
    ref.onDispose(() {
      // 저장 대기 중인 볼륨이 있으면 닫기 전에 바로 저장한다.
      _volumeSave?.cancel();
      if (_pendingVolume case final volume?) settings.volume = volume;
    });
    // 다음 실행 때 이어 볼 수 있도록, 띄운 방송이나 소리 타일이 바뀔 때마다 저장한다.
    listenSelf((previous, next) {
      final ids = [for (final s in next.streams) s.channelId];
      final previousIds = [
        for (final s in previous?.streams ?? const []) s.channelId,
      ];
      if (listEquals(ids, previousIds) &&
          next.audioChannelId == previous?.audioChannelId) {
        return;
      }
      settings.saveSession(ids, next.audioChannelId);
    });
    return MultiviewState(
      volume: settings.volume,
      layoutMode: settings.layoutMode,
    );
  }

  /// 지난 실행에서 띄워 둔 방송을 다시 띄운다. 그사이 끝났거나 불러오지 못한 방송은 건너뛴다.
  Future<void> restoreSession() async {
    // 멤버 동기화가 먼저 방송을 띄우면 그 순간 세션이 새로 저장되므로,
    // 기다리기 전에 저장된 목록부터 읽어 둔다.
    final settings = ref.read(settingsStoreProvider);
    final ids = settings.sessionChannels.take(maxStreams).toList();
    final audioId = settings.sessionAudioChannel;
    if (ids.isEmpty) return;

    final api = ref.read(chzzkApiProvider);
    final lives = await Future.wait([
      for (final id in ids)
        api
            .fetchLive(id)
            .then<LiveInfo?>((live) => live)
            .catchError((_) => null),
    ]);
    if (!ref.mounted) return;

    // 불러오는 동안 멤버 동기화가 띄운 방송은 그대로 두고, 나머지를 저장된 순서대로 붙인다.
    final shown = {for (final s in state.streams) s.channelId};
    final restored = [
      for (final live in lives.nonNulls)
        if (!shown.contains(live.channelId)) live,
    ];
    final streams = [...state.streams, ...restored].take(maxStreams).toList();
    final hasAudio = streams.any((s) => s.channelId == audioId);
    state = state.copyWith(
      streams: streams,
      audioChannelId: hasAudio
          ? () => audioId
          : state.audioChannelId == null && streams.isNotEmpty
          ? () => streams.first.channelId
          : null,
    );
  }

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
    state = state.copyWith(
      streams: streams,
      audioChannelId: () => audioId,
      soloChannelId: state.soloChannelId == channelId ? () => null : null,
    );
  }

  /// 단독 보기를 켜거나 끈다. 켤 때는 그 방송으로 소리도 옮긴다.
  void toggleSolo(String channelId) {
    if (state.soloChannelId == channelId) {
      state = state.copyWith(soloChannelId: () => null);
    } else {
      state = state.copyWith(
        soloChannelId: () => channelId,
        audioChannelId: () => channelId,
        muted: false,
      );
    }
  }

  void exitSolo() => state = state.copyWith(soloChannelId: () => null);

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

  /// [order]에 있는 채널을 그 순서대로 앞에 두고, 나머지는 원래 순서대로 뒤에 둔다.
  /// 멤버 순서대로 타일을 배치하는 데 쓴다.
  void applyOrder(List<String> order) {
    final byId = {for (final s in state.streams) s.channelId: s};
    final ordered = {...order};
    final streams = [
      for (final id in ordered) ?byId[id],
      for (final s in state.streams)
        if (!ordered.contains(s.channelId)) s,
    ];
    if (listEquals(streams, state.streams)) return;
    state = state.copyWith(streams: streams);
  }

  void selectAudio(String channelId) {
    state = state.copyWith(audioChannelId: () => channelId, muted: false);
  }

  void setVolume(double volume) {
    state = state.copyWith(volume: volume, muted: false);
    // 슬라이더를 끄는 동안 매번 쓰지 않도록, 멈추고 잠시 뒤 한 번만 저장한다.
    _pendingVolume = volume;
    _volumeSave?.cancel();
    _volumeSave = Timer(const Duration(milliseconds: 500), () {
      ref.read(settingsStoreProvider).volume = volume;
      _pendingVolume = null;
    });
  }

  void setLayoutMode(LayoutMode mode) {
    state = state.copyWith(layoutMode: mode);
    ref.read(settingsStoreProvider).layoutMode = mode;
  }

  void toggleMute() {
    state = state.copyWith(muted: !state.muted);
  }
}
