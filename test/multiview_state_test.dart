import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:command_center/chzzk_api.dart';
import 'package:command_center/multiview_state.dart';

class _FakeApi extends ChzzkApi {
  @override
  Future<LiveInfo> fetchLive(String channelId) async => LiveInfo(
    channelId: channelId,
    channelName: channelId,
    title: '',
    viewers: 0,
    masterUrl: '',
    variants: const [],
  );
}

String _id(int n) => n.toRadixString(16).padLeft(32, '0');

void main() {
  late ProviderContainer container;
  MultiviewNotifier notifier() => container.read(multiviewProvider.notifier);
  MultiviewState state() => container.read(multiviewProvider);

  setUp(() {
    container = ProviderContainer(
      overrides: [chzzkApiProvider.overrideWithValue(_FakeApi())],
    );
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
}
