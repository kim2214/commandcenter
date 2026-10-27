import 'package:flutter_test/flutter_test.dart';

import 'package:chzzk_multiviewer/chzzk_api.dart';

void main() {
  const id = '792acf9ca28b42918710327e14b06b68';

  test('parseChannelId accepts a bare channel ID', () {
    expect(ChzzkApi.parseChannelId(id), id);
  });

  test('parseChannelId extracts the ID from a live URL', () {
    expect(ChzzkApi.parseChannelId('https://chzzk.naver.com/live/$id'), id);
  });

  test('parseChannelId rejects input without an ID', () {
    expect(ChzzkApi.parseChannelId('hello'), isNull);
  });
}
