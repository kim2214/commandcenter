import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:command_center/chzzk_api.dart';
import 'package:command_center/live_alerts.dart';
import 'package:command_center/members_state.dart';
import 'package:command_center/multiview_state.dart';
import 'package:command_center/settings.dart';

class _FakeApi extends ChzzkApi {
  /// 방송 중인 채널. 여기 없는 채널은 오프라인으로 응답한다.
  final live = <String>{};

  /// live-detail에서 실패하는 채널 (예: 성인 방송).
  final unplayable = <String>{};

  /// live-detail이 일시적으로 실패하는 채널. 한 번 실패한 뒤 비워진다.
  final flaky = <String>{};

  @override
  Future<ChannelInfo> fetchChannel(String channelId) async =>
      ChannelInfo(channelId: channelId, name: 'name-$channelId');

  @override
  Future<LiveStatus> fetchLiveStatus(String channelId) async =>
      LiveStatus(isLive: live.contains(channelId));

  @override
  Future<LiveInfo> fetchLive(String channelId) async {
    if (unplayable.contains(channelId)) {
      throw StreamUnavailableException('성인 방송은 로그인이 필요합니다');
    }
    if (flaky.remove(channelId)) throw ChzzkTimeoutException();
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

class _FakeAlerts implements LiveAlerts {
  final sent = <String>[];

  @override
  Future<void> notifyLive({
    required String channelId,
    required String name,
    required String title,
  }) async => sent.add(channelId);
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

  late SharedPreferences prefs;
  late _FakeAlerts alerts;

  ProviderContainer newContainer() {
    final c = ProviderContainer(
      overrides: [
        chzzkApiProvider.overrideWithValue(api),
        memberStoreProvider.overrideWithValue(store),
        sharedPreferencesProvider.overrideWithValue(prefs),
        liveAlertsProvider.overrideWithValue(alerts),
      ],
    );
    // 실제 앱처럼 동기화를 켜 둔다.
    c.listen(liveSyncProvider, (_, _) {});
    return c;
  }

  setUp(() async {
    api = _FakeApi();
    store = _MemoryStore();
    alerts = _FakeAlerts();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = newContainer();
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

  test('members that are live together are shown in one batch', () async {
    // 등록 중에 도는 확인과 겹치지 않도록, 모두 오프라인인 상태로 등록을 끝낸다.
    await register([1, 2, 3]);
    await sync().poll();
    var changes = 0;
    container.listen(multiviewProvider, (_, _) => changes++);

    api.live.addAll([_id(1), _id(2), _id(3)]);
    await sync().poll();
    expect(shown(), {_id(1), _id(2), _id(3)});
    // 하나씩 추가했다면 세 번 바뀌었을 것이다.
    expect(changes, 1);
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

  test('a transient failure is retried on the next poll', () async {
    api.live.add(_id(1));
    api.flaky.add(_id(1));
    await register([1]);
    await sync().poll();
    expect(shown(), isEmpty);
    expect(container.read(liveSyncProvider).dismissed, isEmpty);

    await sync().poll();
    expect(shown(), {_id(1)});
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

  test('reordering members saves the order and reorders tiles', () async {
    api.live.addAll([_id(1), _id(2), _id(3)]);
    await register([1, 2, 3]);
    await sync().poll();

    // 3번 멤버를 맨 앞으로 옮긴다.
    await container.read(membersProvider.notifier).reorder(2, 0);
    expect(store.saved.map((m) => m.channelId), [_id(3), _id(1), _id(2)]);
    expect(container.read(multiviewProvider).streams.map((s) => s.channelId), [
      _id(3),
      _id(1),
      _id(2),
    ]);
  });

  test(
    'tiles follow member order even when they go live out of order',
    () async {
      await register([1, 2]);
      api.live.add(_id(2));
      await sync().poll();
      api.live.add(_id(1));
      await sync().poll();
      expect(
        container.read(multiviewProvider).streams.map((s) => s.channelId),
        [_id(1), _id(2)],
      );
    },
  );

  test('auto sync setting is restored after restart', () async {
    sync().setAutoSync(false);
    container.dispose();

    container = newContainer();
    expect(container.read(liveSyncProvider).autoSync, isFalse);
  });

  group('live alerts', () {
    test(
      'does not alert for members already live when the app starts',
      () async {
        api.live.add(_id(1));
        await register([1]);
        await sync().poll();
        expect(alerts.sent, isEmpty);
      },
    );

    test('alerts when an offline member goes live', () async {
      await register([1, 2]);
      await sync().poll();
      api.live.add(_id(2));
      await sync().poll();
      expect(alerts.sent, [_id(2)]);

      // 계속 방송 중이면 다시 알리지 않는다.
      await sync().poll();
      expect(alerts.sent, [_id(2)]);
    });

    test(
      'does not alert when alerts are off, and remembers the setting',
      () async {
        sync().setAlerts(false);
        await register([1]);
        await sync().poll();
        api.live.add(_id(1));
        await sync().poll();
        expect(alerts.sent, isEmpty);

        container.dispose();
        container = newContainer();
        expect(container.read(liveSyncProvider).alerts, isFalse);
      },
    );
  });

  group('moving tiles', () {
    List<String> tiles() => [
      for (final s in container.read(multiviewProvider).streams) s.channelId,
    ];

    test('reorders shown members and keeps hidden ones in place', () async {
      api.live.addAll([_id(1), _id(3), _id(4)]);
      await register([1, 2, 3, 4]);
      await sync().poll();
      expect(tiles(), [_id(1), _id(3), _id(4)]);

      // 4번 타일을 1번 자리로 옮긴다.
      await sync().moveTile(_id(4), _id(1));
      expect(tiles(), [_id(4), _id(1), _id(3)]);
      // 방송 중이 아닌 2번은 멤버 목록에서 제자리를 지킨다.
      expect(store.saved.map((m) => m.channelId), [
        _id(4),
        _id(2),
        _id(1),
        _id(3),
      ]);
    });

    test('non-member streams stay after members', () async {
      api.live.addAll([_id(1), _id(2)]);
      await register([1, 2]);
      await sync().poll();
      await container.read(multiviewProvider.notifier).add(_id(9));

      await sync().moveTile(_id(9), _id(1));
      expect(tiles(), [_id(1), _id(2), _id(9)]);
    });
  });
}
