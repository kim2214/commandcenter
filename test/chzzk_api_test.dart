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

  group('stream expiry', () {
    const url =
        'https://ex-nlive-streaming.navercdn.com/chzzk/x/y_hls_playlist.m3u8'
        '?hdnts=st=1792485557~exp=1792546767~acl=*/x/*~hmac=abc';

    test('reads the token expiry from the stream URL', () {
      expect(
        parseStreamExpiry(url),
        DateTime.fromMillisecondsSinceEpoch(1792546767 * 1000, isUtc: true),
      );
    });

    test('returns null when the URL has no expiry', () {
      expect(parseStreamExpiry('https://example.com/live.m3u8'), isNull);
    });

    test('refreshes five minutes before expiry, or right away if late', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(
        streamRefreshDelay(now.add(const Duration(hours: 17)), now),
        const Duration(hours: 16, minutes: 55),
      );
      expect(
        streamRefreshDelay(now.add(const Duration(minutes: 2)), now),
        const Duration(seconds: 5),
      );
    });
  });

  test('fetchLiveStatus reads the stream start time', () async {
    final api = _apiReturning({
      'code': 200,
      'content': {
        'status': 'OPEN',
        'liveTitle': 't',
        'concurrentUserCount': 3,
        'openDate': '2026-10-26 08:28:45',
      },
    });
    final status = await api.fetchLiveStatus(id);
    expect(status.openedAt, DateTime.utc(2026, 10, 25, 23, 28, 45));
  });
}
