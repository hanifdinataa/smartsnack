import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_models.dart';
import '../providers/app_providers.dart';

class HealthMonitoringPage extends ConsumerStatefulWidget {
  const HealthMonitoringPage({super.key});
  @override
  ConsumerState<HealthMonitoringPage> createState() => _HealthMonitoringPageState();
}

class _HealthMonitoringPageState extends ConsumerState<HealthMonitoringPage>
    with TickerProviderStateMixin {
  // ── Countdown constants ──────────────────────────────
  static const int _heartMeasureSeconds = 60;
  static const int _tempMeasureSeconds  = 5;
  static const int _weightMeasureSeconds = 15;
  static const int _heightMeasureSeconds = 10;

  // ── Session state ────────────────────────────────────
  int?    _checkId;
  double? _heartRate;
  double? _bodyTemp;
  double? _weightKg;
  double? _heightCm;

  // ── Loading flags ────────────────────────────────────
  bool _loadingHeartRate = false;
  bool _loadingBodyTemp  = false;
  bool _loadingWeight    = false;
  bool _loadingHeight    = false;
  bool _processing       = false;
  bool _isStreamingWeight = false;
  Timer? _weightStreamTimer;

  // ── Countdown timers ─────────────────────────────────
  int    _heartRemainingSeconds  = 0;
  int    _tempRemainingSeconds   = 0;
  int    _weightRemainingSeconds = 0;
  int    _heightRemainingSeconds = 0;
  Timer? _heartTimer;
  Timer? _tempTimer;
  Timer? _weightTimer;
  Timer? _heightTimer;

  // ── Result ───────────────────────────────────────────
  HealthMonitoringRecord? _result;

  bool _profileInitialized = false;
  final TextEditingController _ageController = TextEditingController();
  String? _selectedGender;

  // ── Animation ────────────────────────────────────────
  late AnimationController _successAnimController;
  late Animation<double>    _successAnim;

  // ── Computed ─────────────────────────────────────────
  double? get _bmi {
    if (_weightKg == null || _heightCm == null) return null;
    if (_weightKg! <= 0 || _heightCm! <= 0) return null;
    final meter = _heightCm! / 100;
    return _weightKg! / (meter * meter);
  }

  String? _localHeartStatus(double? hr) {
    if (hr == null) return null;
    int age = int.tryParse(_ageController.text) ?? 10;
    if (age <= 10) {
      if (hr < 70) return 'rendah';
      if (hr > 120) return 'tinggi';
      return 'normal';
    } else {
      if (hr < 60) return 'rendah';
      if (hr > 100) return 'tinggi';
      return 'normal';
    }
  }

  String? _localTempStatus(double? temp) {
    if (temp == null) return null;
    if (temp < 36.4) return 'rendah';
    if (temp <= 37.5) return 'normal';
    if (temp < 38.0) return 'hangat';
    return 'demam';
  }

  String? _localBmiStatus(double? bmi) {
    if (bmi == null) return null;
    if (bmi < 18.5) return 'underweight';
    if (bmi <= 24.9) return 'normal';
    if (bmi <= 29.9) return 'pre_obese';
    if (bmi <= 34.9) return 'obese_class_1';
    if (bmi <= 39.9) return 'obese_class_2';
    return 'obese_class_3';
  }

  bool get _canProcess =>
      _checkId != null &&
      _heartRate != null &&
      _bodyTemp != null &&
      _weightKg != null &&
      _weightKg! > 0 &&
      _heightCm != null;

  @override
  void initState() {
    super.initState();
    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _successAnim = CurvedAnimation(
      parent: _successAnimController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    _tempTimer?.cancel();
    _weightTimer?.cancel();
    _weightStreamTimer?.cancel();
    _heightTimer?.cancel();
    _successAnimController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // ─── COUNTDOWN HELPERS ───────────────────────────────────────────────────
  void _startCountdown(int seconds, void Function(int) onTick, void Function() onDone, Timer? Function() timerRef) {
    Timer? t;
    t = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      onTick(timer.tick);
      if (timer.tick >= seconds) { timer.cancel(); onDone(); }
    });
  }

  void _startHeartCountdown() {
    setState(() => _heartRemainingSeconds = _heartMeasureSeconds);
    _heartTimer?.cancel();
    _heartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_heartRemainingSeconds <= 1) { timer.cancel(); setState(() => _heartRemainingSeconds = 0); return; }
      setState(() => _heartRemainingSeconds -= 1);
    });
  }

  void _startTempCountdown() {
    setState(() => _tempRemainingSeconds = _tempMeasureSeconds);
    _tempTimer?.cancel();
    _tempTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_tempRemainingSeconds <= 1) { timer.cancel(); setState(() => _tempRemainingSeconds = 0); return; }
      setState(() => _tempRemainingSeconds -= 1);
    });
  }

  void _startWeightCountdown() {
    setState(() => _weightRemainingSeconds = _weightMeasureSeconds);
    _weightTimer?.cancel();
    _weightTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_weightRemainingSeconds <= 1) { timer.cancel(); setState(() => _weightRemainingSeconds = 0); return; }
      setState(() => _weightRemainingSeconds -= 1);
    });
  }

  void _startHeightCountdown() {
    setState(() => _heightRemainingSeconds = _heightMeasureSeconds);
    _heightTimer?.cancel();
    _heightTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_heightRemainingSeconds <= 1) { timer.cancel(); setState(() => _heightRemainingSeconds = 0); return; }
      setState(() => _heightRemainingSeconds -= 1);
    });
  }

  // ─── SENSOR ACTIONS ──────────────────────────────────────────────────────
  Future<void> _checkHeartRate() async {
    _heartTimer?.cancel();
    setState(() { _loadingHeartRate = true; _result = null; });
    _startHeartCountdown();
    _snack('Letakkan jari ke sensor. Sistem mulai mengukur detak jantung...');
    try {
      final map = await ref.read(apiServiceProvider).checkHeartRate(checkId: _checkId);
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) throw Exception('Data detak jantung tidak valid.');
      final nextCheckId   = int.tryParse(raw['check_id'].toString());
      final nextHeartRate = double.tryParse(raw['heart_rate'].toString());
      if (nextHeartRate == null) throw Exception('Data detak jantung dari server tidak lengkap.');
      if (!mounted) return;
      setState(() {
        if (nextCheckId != null) _checkId = nextCheckId;
        _heartRate = nextHeartRate;
        _result = null;
      });
      _snack('✅ Detak jantung berhasil diambil.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _heartTimer?.cancel();
      if (mounted) setState(() { _loadingHeartRate = false; _heartRemainingSeconds = 0; });
    }
  }

  Future<void> _checkBodyTemperature() async {
    _tempTimer?.cancel();
    setState(() { _loadingBodyTemp = true; _result = null; });
    _startTempCountdown();
    _snack('Arahkan dahi ke sensor sampai suhu terbaca...');
    try {
      final map = await ref.read(apiServiceProvider).checkBodyTemperature(checkId: _checkId);
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) throw Exception('Data suhu tubuh tidak valid.');
      final nextCheckId  = int.tryParse(raw['check_id'].toString());
      final nextBodyTemp = double.tryParse(raw['body_temp'].toString());
      if (nextBodyTemp == null) throw Exception('Data suhu tubuh dari server tidak lengkap.');
      if (!mounted) return;
      setState(() {
        if (nextCheckId != null) _checkId = nextCheckId;
        _bodyTemp = nextBodyTemp;
        _result = null;
      });
      _snack('✅ Suhu tubuh berhasil diambil.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _tempTimer?.cancel();
      if (mounted) setState(() { _loadingBodyTemp = false; _tempRemainingSeconds = 0; });
    }
  }

  Future<void> _startWeightStreaming() async {
    _weightTimer?.cancel();
    _weightStreamTimer?.cancel();

    setState(() {
      _isStreamingWeight = true;
      _loadingWeight = true;
      _result = null;
    });

    _snack('Membaca data timbangan secara realtime. Silakan berdiri di atas timbangan.');

    // Jalankan loop polling secara paralel dengan target kecepatan 400ms
    _runWeightStreamLoop();
  }

  Future<void> _runWeightStreamLoop() async {
    while (_isStreamingWeight && mounted) {
      final startTime = DateTime.now();
      await _fetchWeightStream();
      if (!mounted) break;
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      // Target update rate: 400ms
      final delay = 400 - elapsed;
      if (delay > 0) {
        await Future.delayed(Duration(milliseconds: delay));
      } else {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _fetchWeightStream() async {
    try {
      final map = await ref.read(apiServiceProvider).checkWeight(checkId: _checkId);
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) return;
      final nextCheckId = int.tryParse(raw['check_id'].toString());
      final nextWeight  = double.tryParse(raw['weight_kg'].toString());
      if (nextWeight != null && mounted && _isStreamingWeight) {
        setState(() {
          if (nextCheckId != null) _checkId = nextCheckId;
          _weightKg = nextWeight;
          _result = null;
        });
      }
    } catch (e) {
      debugPrint("Streaming error: $e");
    }
  }

  void _stopWeightStreaming() {
    _weightStreamTimer?.cancel();
    setState(() {
      _isStreamingWeight = false;
      _loadingWeight = false;
    });
    _snack('✅ Pengukuran dihentikan. Berat badan terakhir disimpan: ${_weightKg != null ? "${_weightKg!.toStringAsFixed(1)} kg" : "-"}');
  }

  Future<void> _checkWeight() async {
    // Fungsi checkWeight default sekarang memicu mode streaming
    _startWeightStreaming();
  }

  Future<void> _checkHeight() async {
    _heightTimer?.cancel();
    setState(() { _loadingHeight = true; _result = null; });
    _startHeightCountdown();
    _snack('Berdiri tegak di bawah sensor ultrasonik. Sistem mengukur tinggi badan...');
    try {
      final map = await ref.read(apiServiceProvider).checkHeight(checkId: _checkId);
      final raw = map['data'];
      if (raw is! Map<String, dynamic>) throw Exception('Data tinggi badan tidak valid.');
      final nextCheckId = int.tryParse(raw['check_id'].toString());
      final nextHeight  = double.tryParse(raw['height_cm'].toString());
      if (nextHeight == null) throw Exception('Data tinggi badan dari server tidak lengkap.');
      if (!mounted) return;
      setState(() {
        if (nextCheckId != null) _checkId = nextCheckId;
        _heightCm = nextHeight;
        _result = null;
      });
      _snack('✅ Tinggi badan berhasil diambil.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _heightTimer?.cancel();
      if (mounted) setState(() { _loadingHeight = false; _heightRemainingSeconds = 0; });
    }
  }

  Future<void> _process() async {
    final checkId = _checkId;
    if (checkId == null || _heartRate == null) { _snack('Cek Detak Jantung dulu.'); return; }
    if (_bodyTemp == null) { _snack('Cek Suhu Tubuh dulu.'); return; }
    if (_weightKg == null) { _snack('Cek Berat Badan dulu.'); return; }
    if (_heightCm == null) { _snack('Cek Tinggi Badan dulu.'); return; }

    setState(() => _processing = true);
    try {
      final result = await ref.read(apiServiceProvider).analyzeHealthMonitoring(
        checkId: checkId,
        age: int.tryParse(_ageController.text),
        gender: _selectedGender,
      );
      await ref.read(localStorageProvider).saveHealthMonitoringRecord(result);
      await ref.read(localStorageProvider).appendHealthMonitoringHistory(result);
      if (!mounted) return;
      setState(() => _result = result);
      ref.read(profileRefreshSignalProvider.notifier).state++;
      _successAnimController.forward(from: 0);
      _snack(result.isNormal
          ? '🎁 Selamat! Status kesehatan Normal. Kotak snack sedang dibuka!'
          : '⚠️ Status Perlu Perhatian, tapi kotak snack tetap dibuka!');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    if (!_profileInitialized && user != null) {
      if (user.age != null) _ageController.text = user.age.toString();
      if (user.gender != null) _selectedGender = user.gender;
      _profileInitialized = true;
    }
    final bmi  = _bmi;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: const Text('Monitoring Kesehatan', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [

          // ─── Session ID chip ──────────────────────────
          if (_checkId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF0D9F6E)),
                const SizedBox(width: 8),
                Text('Sesi Check ID: $_checkId',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF065F46))),
              ]),
            ),
          ],

          // ─── Profil Anak (read-only dari akun) ────────
          _buildSectionLabel('Profil Anak', Icons.child_care_rounded),
          const SizedBox(height: 12),
          _buildProfileCard(user),
          const SizedBox(height: 24),

          // ─── Sensor Detak Jantung ──────────────────────
          _buildSectionLabel('Data Sensor', Icons.sensors_rounded),
          const SizedBox(height: 12),
          _sensorCard(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFEF4444),
            iconBg: const Color(0xFFFEE2E2),
            title: 'Detak Jantung',
            value: _heartRate == null ? '-' : '${_heartRate!.toStringAsFixed(0)} bpm',
            statusChip: _localHeartStatus(_heartRate) != null
                ? _statusChip(_localHeartStatus(_heartRate)!) : null,
            buttonLabel: _loadingHeartRate ? 'Mengukur...' : 'Cek Detak Jantung',
            hint: 'Letakkan jari pada sensor MAX30102',
            loading: _loadingHeartRate,
            onPressed: _loadingHeartRate ? null : _checkHeartRate,
            countdown: _loadingHeartRate
                ? (_heartRemainingSeconds > 0 ? 'Jari di sensor... ${_heartRemainingSeconds}s' : 'Memproses...')
                : null,
            progress: _loadingHeartRate
                ? ((_heartMeasureSeconds - _heartRemainingSeconds) / _heartMeasureSeconds).clamp(0.0, 1.0)
                : null,
          ),
          const SizedBox(height: 12),

          // ─── Sensor Suhu Tubuh ─────────────────────────
          _sensorCard(
            icon: Icons.thermostat_rounded,
            iconColor: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFEF3C7),
            title: 'Suhu Tubuh',
            value: _bodyTemp == null ? '-' : '${_bodyTemp!.toStringAsFixed(1)} °C',
            statusChip: _localTempStatus(_bodyTemp) != null
                ? _statusChip(_localTempStatus(_bodyTemp)!) : null,
            buttonLabel: _loadingBodyTemp ? 'Membaca...' : 'Cek Suhu Tubuh',
            hint: 'Arahkan dahi ke sensor MLX90614',
            loading: _loadingBodyTemp,
            onPressed: _loadingBodyTemp ? null : _checkBodyTemperature,
            countdown: _loadingBodyTemp
                ? (_tempRemainingSeconds > 0 ? 'Arahkan dahi... ${_tempRemainingSeconds}s' : 'Memproses...')
                : null,
            progress: _loadingBodyTemp
                ? ((_tempMeasureSeconds - _tempRemainingSeconds) / _tempMeasureSeconds).clamp(0.0, 1.0)
                : null,
          ),
          const SizedBox(height: 12),

          // ─── Sensor Berat Badan (LoadCell) ─────────────
          _sensorCard(
            icon: Icons.monitor_weight_rounded,
            iconColor: const Color(0xFF6366F1),
            iconBg: const Color(0xFFEDE9FE),
            title: 'Berat Badan',
            value: _weightKg == null ? '-' : '${_weightKg!.toStringAsFixed(1)} kg',
            statusChip: null,
            buttonLabel: '',
            hint: 'Berdiri di atas timbangan (LoadCell)',
            loading: _loadingWeight,
            onPressed: null,
            countdown: _isStreamingWeight ? 'Mengukur berat badan secara terus menerus (Realtime)...' : null,
            progress: null,
            customButtons: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: _isStreamingWeight ? null : _startWeightStreaming,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9F6E),
                      disabledBackgroundColor: const Color(0xFF0D9F6E).withOpacity(0.3),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: const Text('Mulai', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: _isStreamingWeight ? _stopWeightStreaming : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      disabledBackgroundColor: const Color(0xFFEF4444).withOpacity(0.3),
                    ),
                    icon: const Icon(Icons.stop_rounded, size: 16),
                    label: const Text('Stop', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Berdiri di atas timbangan. Tekan Mulai untuk timbang secara realtime, tekan Stop untuk mengunci.',
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFF6B7280)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ─── Sensor Tinggi Badan (HC-SR04) ─────────────
          _sensorCard(
            icon: Icons.height_rounded,
            iconColor: const Color(0xFF0891B2),
            iconBg: const Color(0xFFCFFAFE),
            title: 'Tinggi Badan',
            value: _heightCm == null ? '-' : '${_heightCm!.toStringAsFixed(1)} cm',
            statusChip: null,
            buttonLabel: _loadingHeight ? 'Mengukur...' : 'Mulai Ukur',
            hint: 'Berdiri tegak di bawah sensor ultrasonik',
            loading: _loadingHeight,
            onPressed: _loadingHeight ? null : _checkHeight,
            countdown: _loadingHeight
                ? (_heightRemainingSeconds > 0 ? 'Berdiri tegak... ${_heightRemainingSeconds}s' : 'Memproses...')
                : null,
            progress: _loadingHeight
                ? ((_heightMeasureSeconds - _heightRemainingSeconds) / _heightMeasureSeconds).clamp(0.0, 1.0)
                : null,
          ),
          const SizedBox(height: 12),

          // ─── BMI read-only ─────────────────────────────
          if (_weightKg != null && _heightCm != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF0F0F0)),
                boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.speed_rounded, color: Color(0xFF0D9F6E), size: 22),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('BMI (dihitung otomatis)', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  const SizedBox(height: 2),
                  Text(
                    bmi == null ? '-' : '${bmi.toStringAsFixed(2)}  •  ${_bmiLabel(bmi)}',
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: bmi == null ? const Color(0xFF9CA3AF) : _bmiColor(bmi),
                    ),
                  ),
                ]),
                if (_localBmiStatus(bmi) != null) ...[
                  const Spacer(),
                  _statusChip(_localBmiStatus(bmi)!),
                ],
              ]),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 16),



          // ─── Tombol Proses ────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_processing || !_canProcess) ? null : _process,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D9F6E),
                disabledBackgroundColor: const Color(0xFFD1FAE5),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _processing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.health_and_safety_rounded, size: 22),
              label: Text(
                _processing ? 'Memproses...' : 'Proses Cek Kesehatan',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // ─── Hasil Cek Kesehatan ───────────────────────
          if (_result != null) ...[
            const SizedBox(height: 24),
            ScaleTransition(
              scale: _successAnim,
              child: _buildResultCard(_result!),
            ),
          ],
        ],
      ),
    );
  }

  // ─── HELPER WIDGETS ───────────────────────────────────────────────────────

  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 20, color: const Color(0xFF0D9F6E)),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827), letterSpacing: -0.2)),
    ]);
  }

  Widget _buildProfileCard(UserModel? user) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D9F6E), Color(0xFF059669)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.child_care_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                user?.name ?? '-',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFF0F0F0)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Umur',
                prefixIcon: const Icon(Icons.cake_outlined, size: 18),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: InputDecoration(
                labelText: 'Gender',
                prefixIcon: const Icon(Icons.wc_outlined, size: 18),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Laki-laki')),
                DropdownMenuItem(value: 'Female', child: Text('Perempuan')),
              ],
              onChanged: (val) {
                setState(() { _selectedGender = val; });
              },
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _sensorCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String value,
    required String buttonLabel,
    required String hint,
    required bool loading,
    required VoidCallback? onPressed,
    Widget? statusChip,
    String? countdown,
    double? progress,
    Widget? customButtons,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827))),
          ])),
          if (statusChip != null) statusChip,
        ]),
        if (countdown != null) ...[
          const SizedBox(height: 8),
          Text(countdown, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
        if (progress != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation(iconColor),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (customButtons != null)
          customButtons
        else
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: iconColor,
                    disabledBackgroundColor: iconColor.withOpacity(0.3),
                  ),
                  icon: Icon(icon, size: 16),
                  label: Text(buttonLabel, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: hint,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFF6B7280)),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _buildResultCard(HealthMonitoringRecord r) {
    final isNormal = r.isNormal;
    final cardColor   = isNormal ? const Color(0xFF0D9F6E) : const Color(0xFFF59E0B);
    final bgColor     = isNormal ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB);
    final borderColor = isNormal ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [BoxShadow(color: cardColor.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        // ── Header ──
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
            child: Icon(isNormal ? Icons.check_circle_rounded : Icons.warning_rounded, size: 32, color: cardColor),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('HASIL CEK KESEHATAN', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(
          isNormal ? 'Status Normal ✅' : 'Perlu Perhatian ⚠️',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: cardColor, letterSpacing: -0.3),
        ),
        const SizedBox(height: 20),

        // ── Per-parameter status ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            _resultRow(Icons.favorite_rounded, const Color(0xFFEF4444), 'Detak Jantung',
                '${r.heartRate.toStringAsFixed(0)} bpm', r.heartStatus),
            const SizedBox(height: 10),
            _resultRow(Icons.thermostat_rounded, const Color(0xFFF59E0B), 'Suhu Tubuh',
                '${r.bodyTemp.toStringAsFixed(1)} °C', r.tempStatus),
            const SizedBox(height: 10),
            _resultRow(Icons.monitor_weight_rounded, const Color(0xFF6366F1), 'Berat Badan',
                '${r.weightKg.toStringAsFixed(1)} kg', null),
            const SizedBox(height: 10),
            _resultRow(Icons.height_rounded, const Color(0xFF0891B2), 'Tinggi Badan',
                '${r.heightCm.toStringAsFixed(1)} cm', null),
            const SizedBox(height: 10),
            _resultRow(Icons.speed_rounded, const Color(0xFF0D9F6E), 'BMI',
                '${r.bmi.toStringAsFixed(2)}  •  ${_bmiLabel(r.bmi)}', r.bmiStatus),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Pesan ──
        if (isNormal) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D9F6E), Color(0xFF059669)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              const Text('🎁', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Kotak Snack Terbuka!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  SizedBox(height: 4),
                  Text('Ambil snack kamu dalam 10 detik ya! Kotak akan menutup otomatis.',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: const Row(children: [
              Text('💪', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tetap semangat menjaga kesehatan! Konsultasikan ke dokter jika diperlukan.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _resultRow(IconData icon, Color color, String label, String value, String? status) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
      ])),
      if (status != null) _statusChip(status),
    ]);
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();

    Color bgColor;
    Color textColor;
    String label;
    IconData icon;

    switch (s) {
      case 'normal':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        label = 'Normal';
        icon = Icons.check_circle_rounded;
        break;
      case 'rendah':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Rendah';
        icon = Icons.warning_rounded;
        break;
      case 'tinggi':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF7F1D1D);
        label = 'Tinggi';
        icon = Icons.warning_rounded;
        break;
      case 'hangat':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Hangat';
        icon = Icons.warning_rounded;
        break;
      case 'demam':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF7F1D1D);
        label = 'Demam';
        icon = Icons.error_rounded;
        break;
      case 'underweight':
      case 'kurus':
        bgColor = const Color(0xFFDDD6FE);
        textColor = const Color(0xFF4C1D95);
        label = 'Underweight';
        icon = Icons.warning_rounded;
        break;
      case 'pre_obese':
      case 'gemuk':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Pre-obese';
        icon = Icons.warning_rounded;
        break;
      case 'obese_class_1':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        label = 'Obese class I';
        icon = Icons.error_rounded;
        break;
      case 'obese_class_2':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF7F1D1D);
        label = 'Obese class II';
        icon = Icons.error_rounded;
        break;
      case 'obese_class_3':
      case 'obesitas':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF581C87);
        label = 'Obese class III';
        icon = Icons.error_rounded;
        break;
      default:
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = status;
        icon = Icons.warning_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: textColor),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
      ]),
    );
  }

  String _bmiLabel(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi <= 24.9) return 'Normal range';
    if (bmi <= 29.9) return 'Pre-obese';
    if (bmi <= 34.9) return 'Obese class I';
    if (bmi <= 39.9) return 'Obese class II';
    return 'Obese class III';
  }

  Color _bmiColor(double bmi) {
    if (bmi < 18.5) return const Color(0xFF7C3AED);
    if (bmi <= 24.9) return const Color(0xFF0D9F6E);
    if (bmi <= 29.9) return const Color(0xFFF59E0B);
    if (bmi <= 34.9) return const Color(0xFFEF4444);
    if (bmi <= 39.9) return const Color(0xFFDC2626);
    return const Color(0xFF991B1B);
  }


}
