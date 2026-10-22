import 'package:flutter_test/flutter_test.dart';

import 'package:command_center/chat_state.dart';
import 'package:command_center/chzzk_api.dart';
import 'package:command_center/multiview_state.dart';

LiveInfo _live(String id) => LiveInfo(
  channelId: id,
  channelName: id,
  title: '',
  viewers: 0,
  masterUrl: '',
  variants: const [],
);

void main() {
  final state = MultiviewState(
    streams: [_live('a'), _live('b'), _live('c')],
    audioChannelId: 'b',
  );

  test('follows the main stream when nothing is pinned', () {
    expect(chatTarget(state, null)?.channelId, 'b');
  });

  test('shows the pinned stream even when the main stream differs', () {
    expect(chatTarget(state, 'c')?.channelId, 'c');
  });

  test('falls back to the main stream when the pinned one was closed', () {
    expect(chatTarget(state, 'gone')?.channelId, 'b');
  });

  test('has no target when no streams are shown', () {
    expect(chatTarget(const MultiviewState(), 'a'), isNull);
  });
}
