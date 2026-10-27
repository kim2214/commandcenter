import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chzzk_multiviewer/update_check.dart';

UpdateChecker _checker(http.Response Function() respond) =>
    UpdateChecker(client: MockClient((_) async => respond()));

http.Response _release(String tag) => http.Response(
  jsonEncode({
    'tag_name': tag,
    'html_url': 'https://github.com/$releaseRepository/releases/tag/$tag',
  }),
  200,
);

void main() {
  group('isNewerVersion', () {
    test('compares major, minor, and patch numerically', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
    });

    test('same or older versions are not newer', () {
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('a release is newer than its prerelease, not the other way', () {
      expect(isNewerVersion('1.1.0', '1.1.0-beta.1'), isTrue);
      expect(isNewerVersion('1.1.0-beta.1', '1.1.0'), isFalse);
    });
  });

  group('UpdateChecker', () {
    test('returns the newer release with its page', () async {
      final update = await _checker(() => _release('v1.1.0')).check('1.0.0');
      expect(update?.version, '1.1.0');
      expect(update?.url, endsWith('/releases/tag/v1.1.0'));
    });

    test('returns null when already up to date', () async {
      expect(await _checker(() => _release('v1.0.0')).check('1.0.0'), isNull);
    });

    test('returns null when there is no release or the API fails', () async {
      expect(
        await _checker(() => http.Response('{}', 404)).check('1.0.0'),
        isNull,
      );
      expect(
        await UpdateChecker(
          client: MockClient((_) => throw http.ClientException('offline')),
        ).check('1.0.0'),
        isNull,
      );
    });
  });
}
