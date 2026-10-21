import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chzzk_api.dart';
import 'multiview_state.dart';

class Member {
  const Member({required this.channelId, required this.name, this.imageUrl});

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    channelId: json['channelId'] as String,
    name: json['name'] as String,
    imageUrl: json['imageUrl'] as String?,
  );

  final String channelId;
  final String name;
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'name': name,
    'imageUrl': imageUrl,
  };
}

/// 멤버 목록을 기기에 저장한다. 테스트에서는 메모리 구현으로 바꿔 끼운다.
class MemberStore {
  static const _key = 'members';

  Future<List<Member>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    return [
      for (final m in jsonDecode(raw) as List)
        Member.fromJson(m as Map<String, dynamic>),
    ];
  }

  Future<void> save(List<Member> members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final m in members) m.toJson()]),
    );
  }
}

final memberStoreProvider = Provider<MemberStore>((ref) => MemberStore());

final membersProvider = AsyncNotifierProvider<MembersNotifier, List<Member>>(
  MembersNotifier.new,
);

class MembersNotifier extends AsyncNotifier<List<Member>> {
  @override
  Future<List<Member>> build() => ref.read(memberStoreProvider).load();

  /// 입력한 채널을 멤버로 등록한다. 실패하면 [ChzzkException]을 던진다.
  Future<void> add(String input) async {
    final channelId = ChzzkApi.parseChannelId(input);
    if (channelId == null) {
      throw ChzzkException('채널 ID 또는 치지직 채널 URL을 입력하세요');
    }
    final current = await future;
    if (current.any((m) => m.channelId == channelId)) {
      throw ChzzkException('이미 등록된 멤버입니다');
    }

    final info = await ref.read(chzzkApiProvider).fetchChannel(channelId);
    final members = [
      ...await future,
      Member(channelId: channelId, name: info.name, imageUrl: info.imageUrl),
    ];
    state = AsyncData(members);
    await ref.read(memberStoreProvider).save(members);
  }

  Future<void> remove(String channelId) async {
    final members = [
      for (final m in await future)
        if (m.channelId != channelId) m,
    ];
    state = AsyncData(members);
    await ref.read(memberStoreProvider).save(members);
  }
}

class LiveSyncState {
  const LiveSyncState({
    this.statuses = const {},
    this.autoSync = true,
    this.dismissed = const {},
  });

  /// 멤버별 마지막으로 확인한 방송 상태. 아직 확인 전이면 키가 없다.
  final Map<String, LiveStatus> statuses;

  /// 켜져 있으면 방송 중인 멤버를 자동으로 띄우고, 끝난 방송은 내린다.
  final bool autoSync;

  /// 방송 중이지만 사용자가 직접 닫은 멤버. 방송이 끝날 때까지 다시 띄우지 않는다.
  final Set<String> dismissed;

  LiveSyncState copyWith({
    Map<String, LiveStatus>? statuses,
    bool? autoSync,
    Set<String>? dismissed,
  }) {
    return LiveSyncState(
      statuses: statuses ?? this.statuses,
      autoSync: autoSync ?? this.autoSync,
      dismissed: dismissed ?? this.dismissed,
    );
  }
}

final liveSyncProvider = NotifierProvider<LiveSyncNotifier, LiveSyncState>(
  LiveSyncNotifier.new,
);

class LiveSyncNotifier extends Notifier<LiveSyncState> {
  static const pollInterval = Duration(seconds: 60);

  Future<void>? _inFlight;

  @override
  LiveSyncState build() {
    final timer = Timer.periodic(pollInterval, (_) => poll());
    ref.onDispose(timer.cancel);
    // 멤버 목록을 처음 불러왔을 때와 바뀔 때마다 바로 확인한다.
    ref.listen(membersProvider, (_, _) => poll());
    return const LiveSyncState();
  }

  /// 모든 멤버의 방송 상태를 확인하고, 자동 동기화가 켜져 있으면 타일에 반영한다.
  /// 이미 확인 중이면 새로 시작하지 않고 진행 중인 확인을 기다린다.
  Future<void> poll() =>
      _inFlight ??= _poll().whenComplete(() => _inFlight = null);

  Future<void> _poll() async {
    final members = ref.read(membersProvider).value;
    if (members == null) return;

    final api = ref.read(chzzkApiProvider);
    final results = await Future.wait([
      for (final m in members)
        api
            .fetchLiveStatus(m.channelId)
            .then<MapEntry<String, LiveStatus>?>(
              (s) => MapEntry(m.channelId, s),
            )
            // 한 명이 실패해도 나머지는 반영하고, 실패한 멤버는 이전 상태를 유지한다.
            .catchError((_) => null),
    ]);
    if (!ref.mounted) return;

    final ids = {for (final m in members) m.channelId};
    final statuses = {
      for (final e in state.statuses.entries)
        if (ids.contains(e.key)) e.key: e.value,
      for (final e in results.nonNulls) e.key: e.value,
    };
    state = state.copyWith(
      statuses: statuses,
      // 방송이 끝난 멤버는 다음 방송 때 다시 자동으로 뜨도록 풀어 준다.
      dismissed: {
        for (final id in state.dismissed)
          if (statuses[id]?.isLive ?? true) id,
      },
    );
    if (state.autoSync) await _sync();
  }

  Future<void> _sync() async {
    final members = ref.read(membersProvider).value ?? const [];
    final multiview = ref.read(multiviewProvider.notifier);
    final shown = {
      for (final s in ref.read(multiviewProvider).streams) s.channelId,
    };

    for (final m in members) {
      final id = m.channelId;
      final isLive = state.statuses[id]?.isLive;
      if (isLive == null) continue;

      if (isLive && !shown.contains(id) && !state.dismissed.contains(id)) {
        try {
          await multiview.add(id);
        } on ChzzkException {
          // 성인 방송처럼 띄울 수 없는 방송은 끝날 때까지 다시 시도하지 않는다.
          state = state.copyWith(dismissed: {...state.dismissed, id});
        } catch (_) {
          // 일시적인 네트워크 오류는 다음 확인 때 다시 시도한다.
        }
        if (!ref.mounted) return;
      } else if (!isLive && shown.contains(id)) {
        multiview.remove(id);
      }
    }
  }

  void setAutoSync(bool value) {
    state = state.copyWith(autoSync: value);
    if (value) _sync();
  }

  /// 사용자가 타일을 닫는다. 멤버라면 방송이 끝날 때까지 자동으로 다시 띄우지 않는다.
  void closeTile(String channelId) {
    final members = ref.read(membersProvider).value ?? const [];
    if (members.any((m) => m.channelId == channelId)) {
      state = state.copyWith(dismissed: {...state.dismissed, channelId});
    }
    ref.read(multiviewProvider.notifier).remove(channelId);
  }

  /// 사용자가 멤버 방송을 직접 띄운다. 실패하면 [ChzzkException]을 던진다.
  Future<void> openTile(String channelId) async {
    state = state.copyWith(dismissed: {...state.dismissed}..remove(channelId));
    await ref.read(multiviewProvider.notifier).add(channelId);
  }
}
