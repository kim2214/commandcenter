import 'package:flutter/material.dart';

import 'chat_panel.dart';
import 'members_panel.dart';

/// 오른쪽 패널. 멤버 목록과 채팅을 탭으로 전환한다.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: const TabBar(
              tabs: [
                Tab(text: '멤버', height: 40),
                Tab(text: '채팅', height: 40),
              ],
            ),
          ),
          // 채팅 탭이 보이지 않으면 채팅 접속도 끊긴다.
          const Expanded(
            child: TabBarView(children: [MembersPanel(), ChatPanel()]),
          ),
        ],
      ),
    );
  }
}
