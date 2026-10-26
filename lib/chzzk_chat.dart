import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chzzk_api.dart';

/// 치지직 채팅 서버(비공식 프로토콜)에 읽기 전용으로 접속하는 클라이언트.
///
/// 치지직 웹이 쓰는 웹소켓 프로토콜을 따른다. 바뀌면 이 파일만 고치면 되도록 분리해 둔다.
/// - `cmd 100`: 접속, `10100`: 접속 응답
/// - `cmd 5101`: 최근 채팅 요청, `15101`: 최근 채팅 응답
/// - `93101`: 실시간 채팅, `93102`: 후원 등 특수 메시지
/// - `cmd 0`: ping, `10000`: pong
class ChzzkChatClient {
  ChzzkChatClient({
    required this._api,
    required this.chatChannelId,
    required this.onMessages,
    required this.onStatus,
  });

  final ChzzkApi _api;
  final String chatChannelId;

  /// 새 메시지가 오면 불린다. [replace]가 true면 최근 채팅 목록이므로 기존 목록을 바꾼다.
  final void Function(List<ChatMessage> messages, {required bool replace})
  onMessages;
  final void Function(ChatStatus status) onStatus;

  WebSocket? _socket;
  Timer? _ping;
  Timer? _retryTimer;
  int _retries = 0;
  bool _closed = false;

  static const _recentMessageCount = 50;

  void start() => _connect();

  void close() {
    _closed = true;
    _retryTimer?.cancel();
    _ping?.cancel();
    _socket?.close();
  }

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final token = await _api.fetchChatAccessToken(chatChannelId);
      // 치지직 웹과 같은 방식으로 채팅방마다 접속할 서버(1~9)를 고른다.
      final server = chatChannelId.codeUnits.fold(0, (a, b) => a + b) % 9 + 1;
      final socket = await WebSocket.connect(
        'wss://kr-ss$server.chat.naver.com/chat',
        headers: {'User-Agent': ChzzkApi.userAgent},
      ).timeout(const Duration(seconds: 10));
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
      _send({
        'cmd': 100,
        'tid': 1,
        'bdy': {
          'uid': null,
          'devType': 2001,
          'accTkn': token,
          'auth': 'READ',
          'libVer': '4.9.3',
          'osVer': Platform.operatingSystem,
          'devName': 'Google Chrome/130',
          'locale': 'ko',
          'timezone': 'Asia/Seoul',
        },
      });
      // 연결이 조용할 때도 끊기지 않도록 주기적으로 ping을 보낸다.
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        _socket?.add(jsonEncode({'ver': '3', 'cmd': 0}));
      });
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onData(dynamic data) {
    if (_closed || data is! String) return;
    // 깨졌거나 모양이 다른 프레임(본문 JSON 포함)은 무시한다. 여기서 던진 예외는 소켓
    // onError로 잡히지 않아 포착되지 않는 오류가 되므로, 한 프레임 때문에 채팅이 조용히
    // 멈추지 않게 처리 전체를 감싼다.
    try {
      final frame = jsonDecode(data) as Map<String, dynamic>;
      switch (frame['cmd']) {
        case 0:
          _socket?.add(jsonEncode({'ver': '3', 'cmd': 10000}));
        case 10100:
          _retries = 0;
          onStatus(ChatStatus.connected);
          _send({
            'cmd': 5101,
            'tid': 2,
            'sid': (frame['bdy'] as Map?)?['sid'],
            'bdy': {'recentMessageCount': _recentMessageCount},
          });
        case final cmd:
          final messages = parseChatFrame(frame);
          if (messages.isNotEmpty) onMessages(messages, replace: cmd == 15101);
      }
    } catch (_) {
      // 한 프레임을 읽지 못해도 접속은 유지하고 다음 프레임을 계속 받는다.
    }
  }

  void _send(Map<String, dynamic> body) {
    _socket?.add(
      jsonEncode({'ver': '3', 'svcid': 'game', 'cid': chatChannelId, ...body}),
    );
  }

  void _onDisconnected() {
    _ping?.cancel();
    _socket = null;
    _scheduleRetry();
  }

  /// 끊기면 2초, 4초, 8초… 최대 30초 간격으로 다시 접속한다.
  void _scheduleRetry() {
    if (_closed) return;
    onStatus(ChatStatus.reconnecting);
    // 2, 4, 8, 16, 30초. 횟수를 계속 키우면 비트 연산이 넘치므로 여기서 멈춘다.
    final seconds = (1 << (_retries + 1)).clamp(2, 30);
    if (_retries < 4) _retries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), _connect);
  }
}

enum ChatStatus { connecting, connected, reconnecting }

enum ChatRole { streamer, manager, viewer }

class ChatMessage {
  ChatMessage({
    required this.nickname,
    required this.text,
    this.emojis = const {},
    this.role = ChatRole.viewer,
    this.isDonation = false,
    this.payAmount = 0,
  });

  /// 익명 후원이면 null이다.
  final String? nickname;

  /// 이모티콘은 `{:이름:}` 형태로 들어 있다. [segments]로 나눠서 그린다.
  final String text;
  final Map<String, String> emojis;
  final ChatRole role;
  final bool isDonation;
  final int payAmount;

  /// 글자와 이모티콘 조각. 그릴 때마다 정규식을 돌리지 않도록 한 번만 나눈다.
  late final List<ChatSegment> segments = splitEmojis(text, emojis);
}

sealed class ChatSegment {
  const ChatSegment();
}

class TextSegment extends ChatSegment {
  const TextSegment(this.text);

  final String text;
}

class EmojiSegment extends ChatSegment {
  const EmojiSegment(this.name, this.url);

  final String name;
  final String url;
}

final _emojiPattern = RegExp(r'\{:([^:{}]+):\}');

/// 메시지를 글자와 이모티콘 조각으로 나눈다. 이미지 주소가 없는 이모티콘은 글자로 남긴다.
List<ChatSegment> splitEmojis(String text, Map<String, String> emojis) {
  final segments = <ChatSegment>[];
  var start = 0;
  for (final match in _emojiPattern.allMatches(text)) {
    final url = emojis[match.group(1)];
    if (url == null) continue;
    if (match.start > start) {
      segments.add(TextSegment(text.substring(start, match.start)));
    }
    segments.add(EmojiSegment(match.group(1)!, url));
    start = match.end;
  }
  if (start < text.length) segments.add(TextSegment(text.substring(start)));
  return segments;
}

/// 채팅 서버가 보낸 한 프레임에서 화면에 보여 줄 메시지를 꺼낸다.
List<ChatMessage> parseChatFrame(Map<String, dynamic> frame) {
  final items = switch (frame['cmd']) {
    93101 || 93102 => frame['bdy'] as List? ?? const [],
    15101 => (frame['bdy'] as Map?)?['messageList'] as List? ?? const [],
    _ => const [],
  };
  return [for (final item in items) ?_parseItem(item as Map<String, dynamic>)];
}

const _chatType = 1;
const _donationType = 10;

ChatMessage? _parseItem(Map<String, dynamic> item) {
  // 최근 채팅(15101)과 실시간 채팅(93101)은 같은 내용을 다른 이름으로 보낸다.
  final text = (item['msg'] ?? item['content']) as String? ?? '';
  final type = (item['msgTypeCode'] ?? item['messageTypeCode']) as int?;
  final status =
      (item['msgStatusType'] ?? item['messageStatusType']) as String?;

  if (status == 'HIDDEN') return null;
  if (type != _chatType && type != _donationType) return null;
  if (type == _chatType && text.isEmpty) return null;

  final profile = _decodeJson(item['profile']);
  final extras = _decodeJson(item['extras']);
  final role = profile?['userRoleCode'] as String? ?? '';

  return ChatMessage(
    nickname: profile?['nickname'] as String?,
    text: text,
    emojis: {
      for (final e in (extras?['emojis'] as Map? ?? const {}).entries)
        e.key as String: e.value as String,
    },
    role: role == 'streamer'
        ? ChatRole.streamer
        : role.contains('manager')
        ? ChatRole.manager
        : ChatRole.viewer,
    isDonation: type == _donationType,
    payAmount: extras?['payAmount'] as int? ?? 0,
  );
}

/// profile과 extras는 JSON 문자열로 한 번 더 감싸서 온다. 비어 있으면 'null' 문자열이다.
Map<String, dynamic>? _decodeJson(Object? value) => switch (value) {
  final String s => jsonDecode(s) as Map<String, dynamic>?,
  final Map<String, dynamic> m => m,
  _ => null,
};
