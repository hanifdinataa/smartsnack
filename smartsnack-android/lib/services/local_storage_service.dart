import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/api_models.dart';

class LocalStorageService {
  LocalStorageService(this._prefs);

  static const _keyToken = 'access_token';
  static const _keyOnboarding = 'onboarding_done';
  static const _keyHealthMonitoring = 'health_monitoring_record';
  static const _keyHealthMonitoringHistory = 'health_monitoring_history';

  final SharedPreferences _prefs;

  String? get token => _prefs.getString(_keyToken);
  bool get onboardingDone => _prefs.getBool(_keyOnboarding) ?? false;

  Future<void> saveToken(String token) async {
    await _prefs.setString(_keyToken, token);
  }

  Future<void> clearToken() async {
    await _prefs.remove(_keyToken);
  }

  Future<void> setOnboardingDone() async {
    await _prefs.setBool(_keyOnboarding, true);
  }

  HealthMonitoringRecord? getHealthMonitoringRecord() {
    final raw = _prefs.getString(_keyHealthMonitoring);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return HealthMonitoringRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveHealthMonitoringRecord(HealthMonitoringRecord record) async {
    await _prefs.setString(_keyHealthMonitoring, jsonEncode(record.toJson()));
  }

  List<HealthMonitoringRecord> getHealthMonitoringHistory() {
    final raw = _prefs.getString(_keyHealthMonitoringHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(HealthMonitoringRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> appendHealthMonitoringHistory(HealthMonitoringRecord record) async {
    final history = getHealthMonitoringHistory();
    final next = <Map<String, dynamic>>[
      record.toJson(),
      ...history.map((e) => e.toJson()),
    ];
    await _prefs.setString(_keyHealthMonitoringHistory, jsonEncode(next));
  }
}
