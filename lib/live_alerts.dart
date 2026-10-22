import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// 멤버가 방송을 시작했을 때 띄우는 알림. 테스트에서는 가짜 구현으로 바꿔 끼운다.
abstract interface class LiveAlerts {
  Future<void> notifyLive({
    required String channelId,
    required String name,
    required String title,
  });
}

final liveAlertsProvider = Provider<LiveAlerts>((ref) => DesktopLiveAlerts());

/// 운영체제 데스크톱 알림. 알림을 누르면 앱 창을 앞으로 가져온다.
class DesktopLiveAlerts implements LiveAlerts {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  // Windows는 알림을 보낼 앱을 고정된 ID로 구분한다. 바꾸면 다른 앱으로 인식된다.
  static const _windowsGuid = '809ed093-fa3a-41be-90b9-ffc7c7b33086';

  /// 처음 알림을 보낼 때 한 번만 초기화한다. 실패하면 알림 없이 넘어간다.
  Future<bool> _initialize() async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          linux: LinuxInitializationSettings(defaultActionName: '열기'),
          macOS: DarwinInitializationSettings(),
          windows: WindowsInitializationSettings(
            appName: 'Chzzk Multiviewer',
            appUserModelId: 'Kim.ChzzkMultiviewer',
            guid: _windowsGuid,
          ),
        ),
        onDidReceiveNotificationResponse: (_) async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('알림을 초기화하지 못했습니다: $e');
      return false;
    }
  }

  @override
  Future<void> notifyLive({
    required String channelId,
    required String name,
    required String title,
  }) async {
    if (!await (_ready ??= _initialize())) return;
    try {
      await _plugin.show(
        id: channelId.hashCode & 0x7fffffff,
        title: '$name 방송 시작',
        body: title,
      );
    } catch (e) {
      debugPrint('알림을 띄우지 못했습니다: $e');
    }
  }
}
