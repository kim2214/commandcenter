import 'dart:math';
import 'dart:ui';

const _aspect = 16 / 9;

enum LayoutMode {
  /// 모든 방송을 같은 크기로 나눈다.
  grid,

  /// 소리가 나는 방송을 크게, 나머지를 작게 둔다.
  focus,
}

/// 메인 + 서브 레이아웃에서 메인 화면이 차지하는 가로 비율.
const mainWidthFraction = 0.72;

/// 방송마다 화면에서 차지할 영역을 방송 순서대로 돌려준다.
///
/// [focus]가 꺼져 있으면 모두 같은 크기로 나눈다. 켜져 있으면 [mainIndex]의
/// 방송을 16:9로 크게 두고, 남는 오른쪽과 아래 영역에 나머지를 채운다.
List<Rect> computeTileRects(
  Size size,
  int count, {
  required bool focus,
  int mainIndex = 0,
}) {
  if (count == 0) return const [];
  final area = Offset.zero & size;
  if (!focus || count == 1) return _evenGrid(area, count);

  // 창이 16:9보다 충분히 세로로 길면 메인을 가로 전체로 쓰고 서브는 아래에 둔다.
  // 아니면 메인을 가로 일부로 줄여 오른쪽과 아래에 서브를 둔다.
  // 어느 쪽이든 메인은 16:9를 유지하고 창 높이를 넘지 않는다.
  final tall = size.height >= size.width / _aspect * 1.25;
  final mainHeight = min(
    size.height,
    size.width * (tall ? 1 : mainWidthFraction) / _aspect,
  );
  final mainWidth = mainHeight * _aspect;
  final main = Rect.fromLTWH(0, 0, mainWidth, mainHeight);
  final right = Rect.fromLTRB(mainWidth, 0, size.width, size.height);
  final bottom = Rect.fromLTRB(0, mainHeight, mainWidth, size.height);

  final subs = _splitSubs(right, bottom, count - 1);
  return [
    for (var i = 0, s = 0; i < count; i++) i == mainIndex ? main : subs[s++],
  ];
}

/// 기존 격자 배치: 열 수를 √n로 정하고 위에서부터 채운다.
List<Rect> _evenGrid(Rect area, int count) {
  final columns = sqrt(count).ceil();
  final rows = (count / columns).ceil();
  return _cells(area, count, columns, rows);
}

/// 서브 화면을 오른쪽과 아래 영역에 나눠 담는다. 가장 작은 서브 화면이
/// 가장 커지는 분배를 고르고, 같으면 오른쪽에 더 많이 둔다.
List<Rect> _splitSubs(Rect right, Rect bottom, int count) {
  List<Rect> best = const [];
  var bestScore = -1.0;
  for (var inRight = count; inRight >= 0; inRight--) {
    final a = _bestPack(right, inRight);
    final b = _bestPack(bottom, count - inRight);
    final score = min(a.tileWidth, b.tileWidth);
    if (score > bestScore) {
      bestScore = score;
      best = [...a.cells, ...b.cells];
    }
  }
  return best;
}

/// 영역에 [count]개를 담을 때 16:9 화면이 가장 커지는 열 수를 찾는다.
({List<Rect> cells, double tileWidth}) _bestPack(Rect area, int count) {
  if (count == 0) return (cells: const [], tileWidth: double.infinity);
  var best = (cells: <Rect>[], tileWidth: -1.0);
  for (var columns = 1; columns <= count; columns++) {
    final rows = (count / columns).ceil();
    final width = _fittedWidth(area.width / columns, area.height / rows);
    if (width > best.tileWidth) {
      best = (cells: _cells(area, count, columns, rows), tileWidth: width);
    }
  }
  return best;
}

/// 칸 안에 16:9 화면을 넣었을 때의 화면 가로 크기.
double _fittedWidth(double cellWidth, double cellHeight) =>
    max(0, min(cellWidth, cellHeight * _aspect));

List<Rect> _cells(Rect area, int count, int columns, int rows) {
  final width = area.width / columns;
  final height = area.height / rows;
  return [
    for (var i = 0; i < count; i++)
      Rect.fromLTWH(
        area.left + (i % columns) * width,
        area.top + (i ~/ columns) * height,
        width,
        height,
      ),
  ];
}
