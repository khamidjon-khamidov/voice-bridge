import 'package:shared_preferences/shared_preferences.dart';

/// Small per-phone preferences.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> open() async => SettingsStore(await SharedPreferences.getInstance());

  String? get hubUrl => _prefs.getString('hubUrl');
  Future<void> setHubUrl(String v) => _prefs.setString('hubUrl', v);

  String? get voice => _prefs.getString('voice');
  Future<void> setVoice(String v) => _prefs.setString('voice', v);

  String get lang => _prefs.getString('lang') ?? 'en-US';
  Future<void> setLang(String v) => _prefs.setString('lang', v);

  bool get autoSend => _prefs.getBool('autoSend') ?? true;
  Future<void> setAutoSend(bool v) => _prefs.setBool('autoSend', v);

  bool get soundOn => _prefs.getBool('soundOn') ?? true;
  Future<void> setSoundOn(bool v) => _prefs.setBool('soundOn', v);

  bool get keepListening => _prefs.getBool('keepListening') ?? true;
  Future<void> setKeepListening(bool v) => _prefs.setBool('keepListening', v);
}
