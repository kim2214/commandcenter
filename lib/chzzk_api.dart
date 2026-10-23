import 'dart:convert';

import 'package:http/http.dart' as http;

/// 치지직 비공식 API 클라이언트.
///
/// 치지직 웹 플레이어가 쓰는 `live-detail` API에서 HLS 주소를 받아온다.
/// 공식 API가 아니므로 응답 구조가 바뀌면 이 파일만 고치면 되도록 분리해 둔다.
class ChzzkApi {
  ChzzkApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

  static final _channelIdPattern = RegExp(r'[0-9a-f]{32}');

  /// 채널 ID(32자리 hex) 또는 `https://chzzk.naver.com/live/{id}` 형태의 URL에서
  /// 채널 ID를 뽑아낸다. 찾지 못하면 null.
  static String? parseChannelId(String input) =>
      _channelIdPattern.firstMatch(input.trim().toLowerCase())?.group(0);

  /// API를 호출해 응답의 `content`를 돌려준다. 채널이 없으면 예외를 던진다.
  /// [path]가 `https://`로 시작하면 다른 호스트의 주소로 그대로 쓴다.
  Future<Map<String, dynamic>> _getContent(String path) async {
    final uri = Uri.parse(
      path.startsWith('https://') ? path : 'https://api.chzzk.naver.com$path',
    );
    final res = await _client.get(uri, headers: {'User-Agent': userAgent});
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

  /// 지금 시청자가 많은 방송의 채널 ID. 성인 방송은 뺀다. 성능 측정 모드에서 쓴다.
  Future<List<String>> fetchPopularChannelIds(int count) async {
    // 성인 방송을 빼고도 count개가 남도록 넉넉히 받는다.
    final content = await _getContent(
      '/service/v1/lives?size=${count * 2}&sortType=POPULAR',
    );
    return [
      for (final live in (content['data'] as List).cast<Map<String, dynamic>>())
        if (live['adult'] != true)
          (live['channel'] as Map<String, dynamic>)['channelId'] as String,
    ].take(count).toList();
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
      throw StreamOfflineException();
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
      chatChannelId: content['chatChannelId'] as String?,
    );
  }

  /// 채팅 서버 접속용 토큰. 로그인하지 않아도 읽기 전용 토큰이 나온다.
  Future<String> fetchChatAccessToken(String chatChannelId) async {
    final content = await _getContent(
      'https://comm-api.game.naver.com/nng_main/v1/chats/access-token'
      '?channelId=$chatChannelId&chatType=STREAMING',
    );
    final token = content['accessToken'] as String?;
    if (token == null) throw ChzzkException('채팅 토큰을 받지 못했습니다');
    return token;
  }

  /// HLS 마스터 플레이리스트를 읽어 화질별 주소 목록을 만든다.
  /// 타일마다 화질을 고를 수 있도록 각 화질의 chunklist 주소를 직접 쓴다.
  Future<List<StreamVariant>> _fetchVariants(String masterUrl) async {
    final masterUri = Uri.parse(masterUrl);
    final res = await _client.get(
      masterUri,
      headers: {'User-Agent': userAgent},
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
    // 화질을 하나도 못 찾으면(응답 형식이 바뀌었거나 비표준 플레이리스트) 여기서 멈춘다.
    // 빈 목록을 그대로 넘기면 타일이 화질을 고를 때 StateError로 죽는다.
    if (variants.isEmpty) {
      throw ChzzkException('재생할 수 있는 화질을 찾을 수 없습니다');
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
    this.chatChannelId,
  });

  final String channelId;
  final String channelName;
  final String title;
  final int viewers;
  final String masterUrl;

  /// 높은 화질 순으로 정렬되어 있다.
  final List<StreamVariant> variants;

  /// 채팅방 ID. 채널 ID와 다르며, 채팅이 꺼진 방송이면 null이다.
  final String? chatChannelId;
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

/// 방송이 꺼져 있다. 네트워크 오류와 달리 다시 시도해도 방송을 켜기 전에는 소용없다.
class StreamOfflineException extends ChzzkException {
  StreamOfflineException() : super('현재 방송 중이 아닙니다');
}
