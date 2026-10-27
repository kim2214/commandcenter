import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chzzk_multiviewer/chzzk_api.dart';
import 'package:chzzk_multiviewer/multiview_state.dart';
import 'package:chzzk_multiviewer/settings.dart';
import 'package:chzzk_multiviewer/tile_layout.dart';

class _FakeApi extends ChzzkApi {
  /// 방송이 끝난 채널.
  final offline = <String>{};

  @override
  Future<LiveInfo> fetchLive(String channelId) async {
    if (offline.contains(channelId)) throw StreamOfflineException();
    return _live(channelId);
  }
}

LiveInfo _live(String channelId) => LiveInfo(
  channelId: channelId,
  channelName: channelId,
  title: '',
  viewers: 0,
  masterUrl: '',
  variants: const [],
);

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

void main() {
  late ProviderContainer container;
  MultiviewNotifier notifier() => container.read(multiviewProvider.notifier);
  MultiviewState state() => container.read(multiviewProvider);

  late SharedPreferences prefs;
  final api = _FakeApi();

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [
      chzzkApiProvider.overrideWithValue(api),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  setUp(() async {
    api.offline.clear();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = newContainer();
  });
  tearDown(() => container.dispose());

  test('first added stream gets audio, later ones do not', () async {
    await notifier().add(_id(1));
    await notifier().add(_id(2));
    expect(state().streams.map((s) => s.channelId), [_id(1), _id(2)]);
    expect(state().audioChannelId, _id(1));
  });

  test('rejects duplicates and invalid input', () async {
    await notifier().add(_id(1));
    expect(() => notifier().add(_id(1)), throwsA(isA<ChzzkException>()));
    expect(() => notifier().add('nope'), throwsA(isA<ChzzkException>()));
  });

  test('rejects more than maxStreams', () async {
    for (var i = 1; i <= MultiviewNotifier.maxStreams; i++) {
      await notifier().add(_id(i));
    }
    expect(() => notifier().add(_id(99)), throwsA(isA<ChzzkException>()));
  });

  test('selectAudio moves audio and unmutes', () async {
    await notifier().add(_id(1));
    await notifier().add(_id(2));
    notifier().toggleMute();
    notifier().selectAudio(_id(2));
    expect(state().audioChannelId, _id(2));
    expect(state().muted, isFalse);
  });

  test(
    'removing the audio stream passes audio to the first remaining',
    () async {
      await notifier().add(_id(1));
      await notifier().add(_id(2));
      await notifier().add(_id(3));
      notifier().selectAudio(_id(2));
      notifier().remove(_id(2));
      expect(state().audioChannelId, _id(1));
      notifier().remove(_id(1));
      notifier().remove(_id(3));
      expect(state().audioChannelId, isNull);
    },
  );

  test('grid quality drops as tiles increase', () async {
    final heights = <int>[];
    for (var i = 1; i <= 10; i++) {
      await notifier().add(_id(i));
      heights.add(state().maxHeightFor(_id(1)));
    }
    expect(heights, [1080, 720, 720, 720, 480, 480, 480, 480, 480, 360]);
  });

  test('focus layout gives the main stream high quality', () async {
    for (var i = 1; i <= 4; i++) {
      await notifier().add(_id(i));
    }
    notifier().setLayoutMode(LayoutMode.focus);
    notifier().selectAudio(_id(3));
    expect(state().mainIndex, 2);
    expect(state().maxHeightFor(_id(3)), 1080);
    expect(state().maxHeightFor(_id(1)), 480);

    await notifier().add(_id(5));
    expect(state().maxHeightFor(_id(1)), 360);
  });

  test('applyOrder puts listed channels first and keeps the rest', () async {
    for (var i = 1; i <= 4; i++) {
      await notifier().add(_id(i));
    }
    notifier().applyOrder([_id(3), _id(9), _id(1)]);
    expect(state().streams.map((s) => s.channelId), [
      _id(3),
      _id(1),
      _id(2),
      _id(4),
    ]);
  });

  test('layout mode and volume are restored after restart', () async {
    notifier().setLayoutMode(LayoutMode.focus);
    notifier().setVolume(40);
    // 볼륨은 잠시 뒤 저장되지만, 닫을 때 대기 중이면 바로 저장된다.
    container.dispose();

    container = newContainer();
    expect(state().layoutMode, LayoutMode.focus);
    expect(state().volume, 40);
  });

  group('session', () {
    List<String> ids() => [for (final s in state().streams) s.channelId];

    test('restores streams in order with the audio tile', () async {
      for (var i = 1; i <= 3; i++) {
        await notifier().add(_id(i));
      }
      notifier().selectAudio(_id(2));
      container.dispose();

      container = newContainer();
      await notifier().restoreSession();
      expect(ids(), [_id(1), _id(2), _id(3)]);
      expect(state().audioChannelId, _id(2));
    });

    test('skips broadcasts that ended since last time', () async {
      for (var i = 1; i <= 3; i++) {
        await notifier().add(_id(i));
      }
      notifier().selectAudio(_id(2));
      container.dispose();

      api.offline.add(_id(2));
      container = newContainer();
      await notifier().restoreSession();
      expect(ids(), [_id(1), _id(3)]);
      // 소리 타일이 사라졌으니 첫 방송으로 넘어간다.
      expect(state().audioChannelId, _id(1));
    });

    test(
      'keeps streams added before restore finished without duplicates',
      () async {
        await notifier().add(_id(1));
        await notifier().add(_id(2));
        container.dispose();

        container = newContainer();
        final restore = notifier().restoreSession();
        // 멤버 동기화가 먼저 띄운 경우
        await notifier().add(_id(2));
        await restore;
        // 어느 쪽이 먼저 끝나든 같은 방송이 두 번 뜨지 않는다.
        expect(ids(), hasLength(2));
        expect(ids().toSet(), {_id(1), _id(2)});
      },
    );

    test('removing every stream clears the saved session', () async {
      await notifier().add(_id(1));
      notifier().remove(_id(1));
      container.dispose();

      container = newContainer();
      await notifier().restoreSession();
      expect(ids(), isEmpty);
    });
  });

  group('solo view', () {
    test('toggles solo and moves audio to it', () async {
      for (var i = 1; i <= 3; i++) {
        await notifier().add(_id(i));
      }
      notifier().toggleMute();
      notifier().toggleSolo(_id(3));
      expect(state().soloIndex, 2);
      expect(state().audioChannelId, _id(3));
      expect(state().muted, isFalse);
      expect(state().maxHeightFor(_id(3)), 1080);

      notifier().toggleSolo(_id(3));
      expect(state().soloChannelId, isNull);
    });

    test('closing the solo stream ends solo view', () async {
      await notifier().add(_id(1));
      await notifier().add(_id(2));
      notifier().toggleSolo(_id(2));
      notifier().remove(_id(2));
      expect(state().soloChannelId, isNull);
    });
  });

  test('move puts a stream at another stream\'s position', () async {
    for (var i = 1; i <= 4; i++) {
      await notifier().add(_id(i));
    }
    List<String> ids() => [for (final s in state().streams) s.channelId];

    notifier().move(_id(4), _id(2));
    expect(ids(), [_id(1), _id(4), _id(2), _id(3)]);
    notifier().move(_id(1), _id(3));
    expect(ids(), [_id(4), _id(2), _id(3), _id(1)]);
  });

  group('addAll', () {
    test('adds several streams in a single state change', () async {
      await notifier().add(_id(1));
      var changes = 0;
      container.listen(multiviewProvider, (_, _) => changes++);

      final failures = await notifier().addAll([_id(2), _id(3), _id(1)]);
      expect(failures, isEmpty);
      expect(state().streams.map((s) => s.channelId), [_id(1), _id(2), _id(3)]);
      expect(changes, 1);
    });

    test('reports failed channels and still adds the rest', () async {
      api.offline.add(_id(2));
      final failures = await notifier().addAll([_id(1), _id(2)]);
      expect(failures.keys, [_id(2)]);
      expect(failures[_id(2)], isA<StreamOfflineException>());
      expect(state().streams.map((s) => s.channelId), [_id(1)]);
      expect(state().audioChannelId, _id(1));
    });
  });
}
