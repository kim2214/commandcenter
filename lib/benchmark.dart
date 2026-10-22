import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'multiview_state.dart';

/// 성능 측정 모드. 환경변수로 켜며, 평소 실행에는 영향이 없다.
///
/// - `CC_BENCH_COUNT=14`: 시청자가 많은 방송 14개를 자동으로 띄운다.
/// - `CC_BENCH_CHANNELS=id1,id2,...`: 정해진 채널을 띄운다. 개선 전후를 같은 방송으로 비교할 때 쓴다.
///
/// 측정 모드에서는 설정과 멤버 목록을 `bench.` 키에 따로 두어 사용자 데이터를 건드리지 않고,
/// 소리가 나지 않도록 음소거로 시작한다.
class Benchmark {
  const Benchmark._(this.count, this.channelIds);

  static Benchmark? fromEnvironment() {
    final env = Platform.environment;
    final channels = env['CC_BENCH_CHANNELS'];
    if (channels != null && channels.isNotEmpty) {
      final ids = channels.split(',').map((s) => s.trim()).toList();
      return Benchmark._(ids.length, ids);
    }
    final count = int.tryParse(env['CC_BENCH_COUNT'] ?? '');
    return count == null ? null : Benchmark._(count, null);
  }

  final int count;
  final List<String>? channelIds;

  static bool get enabled => fromEnvironment() != null;

  Future<void> run(ProviderContainer container) async {
    final multiview = container.read(multiviewProvider.notifier);
    multiview.toggleMute();

    final ids =
        channelIds ??
        await container.read(chzzkApiProvider).fetchPopularChannelIds(count);
    // 같은 방송으로 다시 측정할 수 있게 띄운 채널 목록을 남긴다.
    debugPrint('bench: channels=${ids.join(',')}');

    var added = 0;
    for (final id in ids) {
      try {
        await multiview.add(id);
        added++;
      } catch (e) {
        debugPrint('bench: skip $id ($e)');
      }
    }
    debugPrint('bench: added $added/${ids.length}');
  }
}
