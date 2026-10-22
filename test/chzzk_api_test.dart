import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:command_center/chzzk_api.dart';

ChzzkApi _apiReturning(Map<String, dynamic> body) => ChzzkApi(
  client: MockClient(
    (_) async => http.Response.bytes(utf8.encode(jsonEncode(body)), 200),
  ),
);

void main() {
  const id = '792acf9ca28b42918710327e14b06b68';

  test('fetchLive reports an ended broadcast as StreamOfflineException', () {
    final api = _apiReturning({
      'code': 200,
      'content': {'status': 'CLOSE', 'livePlaybackJson': null},
    });
    expect(api.fetchLive(id), throwsA(isA<StreamOfflineException>()));
  });

  test('fetchLive reports a missing channel as a plain ChzzkException', () {
    final api = _apiReturning({'code': 200, 'content': null});
    expect(
      api.fetchLive(id),
      throwsA(
        allOf(isA<ChzzkException>(), isNot(isA<StreamOfflineException>())),
      ),
    );
  });
}
