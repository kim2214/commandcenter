import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:command_center/chzzk_chat.dart';

String _profile(String nickname, {String role = 'common_user'}) =>
    jsonEncode({'nickname': nickname, 'userRoleCode': role});

void main() {
  test('parses live chat messages (93101)', () {
    final messages = parseChatFrame({
      'cmd': 93101,
      'bdy': [
        {
          'msg': '안녕하세요',
          'msgTypeCode': 1,
          'msgStatusType': 'NORMAL',
          'profile': _profile('시청자'),
          'extras': jsonEncode({'osType': 'PC'}),
        },
        {
          'msg': '공지',
          'msgTypeCode': 1,
          'profile': _profile('방장', role: 'streamer'),
          'extras': 'null',
        },
        {
          'msg': '도와드릴게요',
          'msgTypeCode': 1,
          'profile': _profile('매니저', role: 'streaming_chat_manager'),
          'extras': 'null',
        },
      ],
    });
    expect(messages.map((m) => m.nickname), ['시청자', '방장', '매니저']);
    expect(messages.map((m) => m.role), [
      ChatRole.viewer,
      ChatRole.streamer,
      ChatRole.manager,
    ]);
    expect(messages.first.text, '안녕하세요');
    expect(messages.first.isDonation, isFalse);
  });

  test('parses recent messages (15101) with their different field names', () {
    final messages = parseChatFrame({
      'cmd': 15101,
      'bdy': {
        'messageList': [
          {
            'content': '예전 채팅',
            'messageTypeCode': 1,
            'messageStatusType': 'NORMAL',
            'profile': _profile('누군가'),
            'extras': 'null',
          },
        ],
      },
    });
    expect(messages.single.text, '예전 채팅');
    expect(messages.single.nickname, '누군가');
  });

  test('parses anonymous donations (93102)', () {
    final messages = parseChatFrame({
      'cmd': 93102,
      'bdy': [
        {
          'msg': '응원합니다',
          'msgTypeCode': 10,
          'profile': 'null',
          'extras': jsonEncode({'payAmount': 1000, 'isAnonymous': true}),
        },
      ],
    });
    final donation = messages.single;
    expect(donation.isDonation, isTrue);
    expect(donation.payAmount, 1000);
    expect(donation.nickname, isNull);
  });

  test('skips hidden, system, and empty messages', () {
    final messages = parseChatFrame({
      'cmd': 93101,
      'bdy': [
        {'msg': '가려짐', 'msgTypeCode': 1, 'msgStatusType': 'HIDDEN'},
        {'msg': '시스템', 'msgTypeCode': 30},
        {'msg': '', 'msgTypeCode': 1},
      ],
    });
    expect(messages, isEmpty);
  });

  test('ignores frames that are not chat', () {
    expect(parseChatFrame({'cmd': 0}), isEmpty);
    expect(parseChatFrame({'cmd': 10100, 'bdy': {}}), isEmpty);
  });

  test('splits emojis that have an image and keeps unknown ones as text', () {
    final segments = splitEmojis('a{:smile:}b{:unknown:}', {
      'smile': 'https://example.com/smile.png',
    });
    expect(segments, hasLength(3));
    expect((segments[0] as TextSegment).text, 'a');
    expect((segments[1] as EmojiSegment).url, 'https://example.com/smile.png');
    expect((segments[2] as TextSegment).text, 'b{:unknown:}');
  });

  test('emoji-only message has no text segments', () {
    final segments = splitEmojis('{:a:}{:b:}', {'a': 'u1', 'b': 'u2'});
    expect(segments.whereType<TextSegment>(), isEmpty);
    expect(segments.whereType<EmojiSegment>().map((e) => e.name), ['a', 'b']);
  });
}
