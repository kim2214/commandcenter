import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'benchmark.dart';

/// 릴리스를 올리는 GitHub 저장소.
// 저장소 이름을 바꿔도 GitHub가 옛 주소(kim2214/commandcenter)를 넘겨주지만, 새 이름을 쓴다.
const releaseRepository = 'kim2214/ChzzkMultiviewer';

class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.url});

  /// 예: `1.1.0`
  final String version;

  /// 릴리스 페이지 주소.
  final String url;
}

/// GitHub의 최신 정식 릴리스를 확인한다. 시험판과 초안은 GitHub가 알아서 뺀다.
class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// [currentVersion]보다 새 릴리스가 있으면 돌려준다. 없거나 확인하지 못하면 null.
  Future<AvailableUpdate?> check(String currentVersion) async {
    try {
      final res = await _client
          .get(
            Uri.parse(
              'https://api.github.com/repos/$releaseRepository/releases/latest',
            ),
            // GitHub API는 User-Agent가 없으면 요청을 거절한다.
            headers: {
              'User-Agent': 'chzzk-multiviewer',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String?;
      final url = body['html_url'] as String?;
      if (tag == null || url == null) return null;

      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!isNewerVersion(latest, currentVersion)) return null;
      return AvailableUpdate(version: latest, url: url);
    } catch (e) {
      // 오프라인이거나 API 제한에 걸리면 조용히 넘어간다.
      debugPrint('새 버전을 확인하지 못했습니다: $e');
      return null;
    } finally {
      _client.close();
    }
  }
}

/// [candidate]가 [current]보다 새 버전인지. `1.2.3`, `1.2.3-beta.1` 형태를 비교한다.
/// 숫자가 같으면 시험판보다 정식 버전이 새 버전이다.
bool isNewerVersion(String candidate, String current) {
  final (a, aPre) = _parse(candidate);
  final (b, bPre) = _parse(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return !aPre && bPre;
}

(List<int>, bool) _parse(String version) {
  final [core, ...pre] = version.split('-');
  final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return (parts, pre.isNotEmpty);
}

/// 앱을 켤 때 한 번 확인한다. 측정 모드에서는 확인하지 않는다.
final availableUpdateProvider = FutureProvider<AvailableUpdate?>((ref) async {
  if (Benchmark.enabled) return null;
  final info = await PackageInfo.fromPlatform();
  return UpdateChecker().check(info.version);
});
