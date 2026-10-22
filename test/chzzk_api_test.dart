import 'dart:async';
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

  test('a request that never answers fails with a timeout error', () async {
    final api = ChzzkApi(
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      api.fetchLiveStatus(id),
      throwsA(isA<ChzzkTimeoutException>()),
    );
  });

  test('an adult broadcast is reported as unavailable', () {
    final api = _apiReturning({
      'code': 200,
      'content': {'status': 'OPEN', 'livePlaybackJson': null, 'adult': true},
    });
    expect(api.fetchLive(id), throwsA(isA<StreamUnavailableException>()));
  });
}
