/// 화면에 보여 줄 숫자와 시간 표기.
library;

/// 세 자리마다 쉼표를 넣는다. 19598 → "19,598".
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 방송 경과 시간. "45분", "2시간 15분", "1일 3시간"처럼 두 단위까지만 보여 준다.
String formatElapsed(Duration elapsed) {
  if (elapsed.isNegative) elapsed = Duration.zero;
  final days = elapsed.inDays;
  final hours = elapsed.inHours % 24;
  final minutes = elapsed.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days일 $hours시간' : '$days일';
  if (hours > 0) return minutes > 0 ? '$hours시간 $minutes분' : '$hours시간';
  return '$minutes분';
}

/// 치지직이 주는 `2026-10-26 08:28:45` 형식의 시각을 읽는다. 시간대 표시가 없지만
/// 한국 시간이므로 UTC+9로 해석해, 다른 시간대 PC에서도 경과 시간이 맞게 한다.
DateTime? parseChzzkDateTime(String? value) {
  if (value == null) return null;
  return DateTime.tryParse('${value.replaceFirst(' ', 'T')}+09:00');
}
