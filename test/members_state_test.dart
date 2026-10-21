import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:command_center/chzzk_api.dart';
import 'package:command_center/members_state.dart';
import 'package:command_center/multiview_state.dart';

class _FakeApi extends ChzzkApi {
  /// 방송 중인 채널. 여기 없는 채널은 오프라인으로 응답한다.
  final live = <String>{};

  /// live-detail에서 실패하는 채널 (예: 성인 방송).
  final unplayable = <String>{};

  @override
  Future<ChannelInfo> fetchChannel(String channelId) async =>
      ChannelInfo(channelId: channelId, name: 'name-$channelId');

  @override
  Future<LiveStatus> fetchLiveStatus(String channelId) async =>
      LiveStatus(isLive: live.contains(channelId));

  @override
  Future<LiveInfo> fetchLive(String channelId) async {
    if (unplayable.contains(channelId)) {
      throw ChzzkException('성인 방송은 로그인이 필요합니다');
    }
    return LiveInfo(
      channelId: channelId,
      channelName: channelId,
      title: '',
      viewers: 0,
      masterUrl: '',
      variants: const [],
    );
  }
}

class _MemoryStore extends MemberStore {
  List<Member> saved = const [];

  @override
  Future<List<Member>> load() async => saved;

  @override
  Future<void> save(List<Member> members) async => saved = members;
}

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

void main() {
  late _FakeApi api;
  late _MemoryStore store;
  late ProviderContainer container;

  Set<String> shown() => {
    for (final s in container.read(multiviewProvider).streams) s.channelId,
  };
  LiveSyncNotifier sync() => container.read(liveSyncProvider.notifier);

  setUp(() {
    api = _FakeApi();
    store = _MemoryStore();
    container = ProviderContainer(
      overrides: [
        chzzkApiProvider.overrideWithValue(api),
        memberStoreProvider.overrideWithValue(store),
      ],
    );
    // 실제 앱처럼 동기화를 켜 둔다.
    container.listen(liveSyncProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  Future<void> register(List<int> ids) async {
    for (final n in ids) {
      await container.read(membersProvider.notifier).add(_id(n));
    }
  }

  test('registering members saves them to the store', () async {
    await register([1, 2]);
    expect(store.saved.map((m) => m.name), [
      'name-${_id(1)}',
      'name-${_id(2)}',
    ]);
    expect(
      () => container.read(membersProvider.notifier).add(_id(1)),
      throwsA(isA<ChzzkException>()),
    );
  });

  test('removing a member saves the change', () async {
    await register([1, 2]);
    await container.read(membersProvider.notifier).remove(_id(1));
    expect(store.saved.map((m) => m.channelId), [_id(2)]);
  });

  test('poll shows live members and removes ended ones', () async {
    api.live.addAll([_id(1), _id(2)]);
    await register([1, 2, 3]);
    await sync().poll();
    expect(shown(), {_id(1), _id(2)});

    api.live.remove(_id(1));
    await sync().poll();
    expect(shown(), {_id(2)});
  });

  test('closed tile stays closed until that broadcast ends', () async {
    api.live.add(_id(1));
    await register([1]);
    await sync().poll();
    sync().closeTile(_id(1));

    await sync().poll();
    expect(shown(), isEmpty);

    // 방송이 끝났다가 다시 켜지면 자동으로 뜬다.
    api.live.remove(_id(1));
    await sync().poll();
    api.live.add(_id(1));
    await sync().poll();
    expect(shown(), {_id(1)});
  });

  test('openTile shows a dismissed member again', () async {
    api.live.add(_id(1));
    await register([1]);
    await sync().poll();
    sync().closeTile(_id(1));
    await sync().openTile(_id(1));
    expect(shown(), {_id(1)});
  });

  test('unplayable broadcasts are not retried every poll', () async {
    api.live.add(_id(1));
    api.unplayable.add(_id(1));
    await register([1]);
    await sync().poll();
    expect(shown(), isEmpty);
    expect(container.read(liveSyncProvider).dismissed, {_id(1)});
  });

  test('auto sync off leaves tiles alone', () async {
    api.live.add(_id(1));
    // 멤버를 등록하는 순간에도 확인이 돌기 때문에 먼저 끈다.
    sync().setAutoSync(false);
    await register([1]);
    await sync().poll();
    expect(shown(), isEmpty);
    expect(container.read(liveSyncProvider).statuses[_id(1)]?.isLive, isTrue);
  });
}
