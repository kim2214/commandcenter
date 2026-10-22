import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tile_layout.dart';

/// 앱 시작 시 `main()`에서 열어 둔 저장소를 넣어 준다.
/// 덕분에 상태를 처음 만들 때 저장된 설정을 기다리지 않고 바로 읽을 수 있다.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main()에서 overrideWithValue로 넣어야 합니다'),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

/// 다시 켰을 때 이어서 쓸 사용자 설정.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _layoutModeKey = 'layoutMode';
  static const _volumeKey = 'volume';
  static const _autoSyncKey = 'autoSync';
  static const _liveAlertsKey = 'liveAlerts';
  static const _sessionChannelsKey = 'sessionChannels';
  static const _sessionAudioKey = 'sessionAudioChannel';

  LayoutMode get layoutMode =>
      LayoutMode.values.asNameMap()[_prefs.getString(_layoutModeKey)] ??
      LayoutMode.grid;
  set layoutMode(LayoutMode value) =>
      _prefs.setString(_layoutModeKey, value.name);

  double get volume => _prefs.getDouble(_volumeKey) ?? 100;
  set volume(double value) => _prefs.setDouble(_volumeKey, value);

  bool get autoSync => _prefs.getBool(_autoSyncKey) ?? true;
  set autoSync(bool value) => _prefs.setBool(_autoSyncKey, value);

  bool get liveAlerts => _prefs.getBool(_liveAlertsKey) ?? true;
  set liveAlerts(bool value) => _prefs.setBool(_liveAlertsKey, value);

  /// 마지막으로 띄워 둔 방송의 채널 ID (화면 순서대로).
  List<String> get sessionChannels =>
      _prefs.getStringList(_sessionChannelsKey) ?? const [];

  /// 마지막으로 소리가 나던 방송의 채널 ID.
  String? get sessionAudioChannel => _prefs.getString(_sessionAudioKey);

  void saveSession(List<String> channels, String? audioChannel) {
    _prefs.setStringList(_sessionChannelsKey, channels);
    if (audioChannel == null) {
      _prefs.remove(_sessionAudioKey);
    } else {
      _prefs.setString(_sessionAudioKey, audioChannel);
    }
  }
}
