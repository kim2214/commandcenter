import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:chzzk_multiviewer/tile_layout.dart';

void main() {
  const size = Size(1600, 900);

  bool overlaps(Rect a, Rect b) {
    final i = a.intersect(b);
    return i.width > 0.5 && i.height > 0.5;
  }

  void expectNoOverlapInside(List<Rect> rects, [Size size = size]) {
    final area = Offset.zero & size;
    for (final r in rects) {
      expect(area.inflate(0.5).contains(r.topLeft), isTrue);
      expect(area.inflate(0.5).contains(r.bottomRight), isTrue);
    }
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(overlaps(rects[i], rects[j]), isFalse, reason: '$i and $j');
      }
    }
  }

  test('grid splits evenly like before', () {
    final rects = computeTileRects(size, 4, focus: false);
    expect(rects, [
      const Rect.fromLTWH(0, 0, 800, 450),
      const Rect.fromLTWH(800, 0, 800, 450),
      const Rect.fromLTWH(0, 450, 800, 450),
      const Rect.fromLTWH(800, 450, 800, 450),
    ]);
  });

  test('single stream fills the screen in focus mode', () {
    expect(computeTileRects(size, 1, focus: true), [Offset.zero & size]);
  });

  test('main stream is the largest and keeps 16:9', () {
    for (var count = 2; count <= 16; count++) {
      final rects = computeTileRects(size, count, focus: true, mainIndex: 1);
      final main = rects[1];
      expect(main.width / main.height, closeTo(16 / 9, 0.01));
      for (final (i, r) in rects.indexed) {
        if (i != 1) {
          expect(r.width * r.height, lessThan(main.width * main.height));
        }
      }
      expectNoOverlapInside(rects);
    }
  });

  test('subs keep their order around the main stream', () {
    final rects = computeTileRects(size, 4, focus: true, mainIndex: 0);
    // 오른쪽 열에 위에서부터 차례로 쌓인다.
    expect(rects[1].top, lessThan(rects[2].top));
    expect(rects[2].top, lessThan(rects[3].top));
  });

  test('tall windows use a full-width main with subs below', () {
    const tall = Size(900, 1600);
    final rects = computeTileRects(tall, 3, focus: true);
    expectNoOverlapInside(rects, tall);
    expect(rects[0].width, 900);
    for (final r in rects.skip(1)) {
      expect(r.top, greaterThanOrEqualTo(rects[0].bottom - 0.5));
    }
  });

  test('solo view fills the screen with one stream and hides the rest', () {
    for (final focus in [false, true]) {
      final rects = computeTileRects(size, 4, focus: focus, soloIndex: 2);
      expect(rects[2], Offset.zero & size);
      for (final i in [0, 1, 3]) {
        expect(rects[i].isEmpty, isTrue);
      }
    }
  });
}
