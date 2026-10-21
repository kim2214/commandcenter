import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'benchmark.dart';
import 'multiview_page.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final benchmark = Benchmark.fromEnvironment();
  // 측정 모드에서는 사용자 설정과 멤버 목록을 건드리지 않도록 따로 떼어 둔 키를 쓰고,
  // 매번 빈 상태로 시작한다.
  if (benchmark != null) SharedPreferences.setPrefix('bench.');
  final prefs = await SharedPreferences.getInstance();
  if (benchmark != null) await prefs.clear();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
  await benchmark?.run(container);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chzzk Multiviewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const MultiviewPage(),
    );
  }
}
