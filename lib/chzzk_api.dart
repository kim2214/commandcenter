import 'dart:convert';

import 'package:http/http.dart' as http;

/// 치지직 비공식 API 클라이언트.
///
/// 치지직 웹 플레이어가 쓰는 `live-detail` API에서 HLS 주소를 받아온다.
/// 공식 API가 아니므로 응답 구조가 바뀌면 이 파일만 고치면 되도록 분리해 둔다.
class ChzzkApi {
  ChzzkApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

  static final _channelIdPattern = RegExp(r'[0-9a-f]{32}');

  /// 채널 ID(32자리 hex) 또는 `https://chzzk.naver.com/live/{id}` 형태의 URL에서
  /// 채널 ID를 뽑아낸다. 찾지 못하면 null.
  static String? parseChannelId(String input) =>
      _channelIdPattern.firstMatch(input.trim().toLowerCase())?.group(0);

  /// API를 호출해 응답의 `content`를 돌려준다. 채널이 없으면 예외를 던진다.
  Future<Map<String, dynamic>> _getContent(String path) async {
    final uri = Uri.parse('https://api.chzzk.naver.com$path');
    final res = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) {
      throw ChzzkException('API 요청 실패 (HTTP ${res.statusCode})');
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final content = body['content'] as Map<String, dynamic>?;
    if (content == null) {
      throw ChzzkException('채널을 찾을 수 없습니다');
    }
    return content;
  }

  /// 멤버 등록용 채널 정보. 방송 중이 아니어도 조회된다.
  Future<ChannelInfo> fetchChannel(String channelId) async {
    final content = await _getContent('/service/v1/channels/$channelId');
    // 없는 채널도 200으로 응답하고 channelId만 null로 내려온다.
    if (content['channelId'] == null) {
      throw ChzzkException('채널을 찾을 수 없습니다');
    }
    return ChannelInfo(
      channelId: channelId,
      name: content['channelName'] as String? ?? '',
      imageUrl: content['channelImageUrl'] as String?,
    );
  }

  /// 방송 중인지만 가볍게 확인한다. 주기적인 상태 확인에 쓴다.
  Future<LiveStatus> fetchLiveStatus(String channelId) async {
    final content = await _getContent(
      '/polling/v3/channels/$channelId/live-status',
    );
    return LiveStatus(
      isLive: content['status'] == 'OPEN',
      title: content['liveTitle'] as String? ?? '',
      viewers: content['concurrentUserCount'] as int? ?? 0,
    );
  }

  Future<LiveInfo> fetchLive(String channelId) async {
    final content = await _getContent(
      '/service/v3/channels/$channelId/live-detail',
    );

    final channel = content['channel'] as Map<String, dynamic>? ?? const {};
    final status = content['status'] as String?;
    final playbackJson = content['livePlaybackJson'] as String?;

    if (status != 'OPEN') {
      throw ChzzkException('현재 방송 중이 아닙니다');
    }
    if (playbackJson == null) {
      // 성인 방송은 로그인 쿠키 없이는 재생 정보가 내려오지 않는다.
      throw ChzzkException(
        content['adult'] == true ? '성인 방송은 로그인이 필요합니다' : '재생 정보가 없습니다',
      );
    }

    final playback = jsonDecode(playbackJson) as Map<String, dynamic>;
    final media = (playback['media'] as List).cast<Map<String, dynamic>>();
    final hls = media.firstWhere(
      (m) => m['mediaId'] == 'HLS',
      orElse: () => throw ChzzkException('HLS 스트림을 찾을 수 없습니다'),
    );
    final masterUrl = hls['path'] as String;

    return LiveInfo(
      channelId: channelId,
      channelName: channel['channelName'] as String? ?? '',
      title: content['liveTitle'] as String? ?? '',
      viewers: content['concurrentUserCount'] as int? ?? 0,
      masterUrl: masterUrl,
      variants: await _fetchVariants(masterUrl),
    );
  }

  /// HLS 마스터 플레이리스트를 읽어 화질별 주소 목록을 만든다.
  /// 타일마다 화질을 고를 수 있도록 각 화질의 chunklist 주소를 직접 쓴다.
  Future<List<StreamVariant>> _fetchVariants(String masterUrl) async {
    final masterUri = Uri.parse(masterUrl);
    final res = await _client.get(
      masterUri,
      headers: {'User-Agent': _userAgent},
    );
    if (res.statusCode != 200) {
      throw ChzzkException('플레이리스트 요청 실패 (HTTP ${res.statusCode})');
    }

    final variants = <StreamVariant>[];
    int? height;
    for (final raw in const LineSplitter().convert(res.body)) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final match = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
        height = match == null ? null : int.parse(match.group(1)!);
      } else if (line.isNotEmpty && !line.startsWith('#') && height != null) {
        variants.add(
          StreamVariant(
            height: height,
            url: masterUri.resolve(line).toString(),
          ),
        );
        height = null;
      }
    }
    variants.sort((a, b) => b.height.compareTo(a.height));
    return variants;
  }

  void close() => _client.close();
}

class LiveInfo {
  const LiveInfo({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.viewers,
    required this.masterUrl,
    required this.variants,
  });

  final String channelId;
  final String channelName;
  final String title;
  final int viewers;
  final String masterUrl;

  /// 높은 화질 순으로 정렬되어 있다.
  final List<StreamVariant> variants;
}

class ChannelInfo {
  const ChannelInfo({
    required this.channelId,
    required this.name,
    this.imageUrl,
  });

  final String channelId;
  final String name;
  final String? imageUrl;
}

class LiveStatus {
  const LiveStatus({required this.isLive, this.title = '', this.viewers = 0});

  final bool isLive;
  final String title;
  final int viewers;
}

class StreamVariant {
  const StreamVariant({required this.height, required this.url});

  final int height;
  final String url;

  String get label => '${height}p';
}

class ChzzkException implements Exception {
  ChzzkException(this.message);

  final String message;

  @override
  String toString() => message;
}
