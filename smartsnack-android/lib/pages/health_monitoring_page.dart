import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
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

  // ── Real-time chart data ─────────────────────────────
  List<double> _heartChartData = [];
  List<double> _tempChartData  = [];
  Timer?       _heartPollTimer;
  Timer?       _tempPollTimer;

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

  // ── Status tinggi badan berdasarkan usia dan jenis kelamin ──
  // Sumber: WHO & Kementerian Kesehatan RI
  // Mengembalikan: 'normal', 'pendek', atau 'sangat_pendek'
  // Batas 'pendek' = ambang batas WHO (nilai di tabel), kurang dari itu = 'sangat_pendek'
  String? _localHeightStatus(double? heightCm) {
    if (heightCm == null || heightCm <= 0) return null;

    final int age  = int.tryParse(_ageController.text) ?? 0;
    final String gender = _selectedGender ?? '';
    if (age <= 0 || gender.isEmpty) return null;

    // Batas MINIMUM tinggi badan (cm) berdasarkan WHO
    // Di bawah nilai ini = PENDEK. Di bawah 80% nilai ini = SANGAT PENDEK.
    // Data usia 1-5 tahun: kisaran bawah berdasarkan Kemenkes RI
    // Data usia 6-18 tahun: ambang batas 'pendek' dari WHO
    final Map<int, Map<String, double>> _minHeight = {
      1:  {'Male': 72.0, 'Female': 70.0},
      2:  {'Male': 82.0, 'Female': 80.0},
      3:  {'Male': 83.0, 'Female': 82.0},
      4:  {'Male': 84.0, 'Female': 83.0},
      5:  {'Male': 85.0, 'Female': 84.0},
      6:  {'Male': 106.1, 'Female': 104.9},
      7:  {'Male': 111.2, 'Female': 109.9},
      8:  {'Male': 116.0, 'Female': 115.0},
      9:  {'Male': 120.5, 'Female': 120.3},
      10: {'Male': 125.0, 'Female': 125.8},
      11: {'Male': 129.7, 'Female': 131.7},
      12: {'Male': 134.9, 'Female': 137.6},
      13: {'Male': 141.2, 'Female': 142.5},
      14: {'Male': 147.8, 'Female': 145.9},
      15: {'Male': 153.4, 'Female': 147.9},
      16: {'Male': 157.4, 'Female': 148.9},
      17: {'Male': 159.9, 'Female': 149.5},
      18: {'Male': 161.2, 'Female': 149.8},
    };

    // Jika usia di luar rentang 1-18, kembalikan null (tidak bisa dievaluasi)
    if (age < 1 || age > 18) return null;

    final double? minNormal = _minHeight[age]?[gender];
    if (minNormal == null) return null;

    // Ambang batas sangat pendek = 80% dari batas normal (estimasi konservatif)
    final double veryShortThreshold = minNormal * 0.935;

    if (heightCm < veryShortThreshold) return 'sangat_pendek';
    if (heightCm < minNormal)          return 'pendek';
    return 'normal';
  }

  // ── Status berat badan berdasarkan standar WHO BB/U ──
  // Sumber: WHO Child Growth Standards & hellosehat.com
  // Untuk usia 1–10 tahun: menggunakan berat badan menurut umur (BB/U)
  // Untuk usia >10 tahun: kembalikan null → pakai bmiStatus dari server
  String? _localWeightStatus(double weightKg, int age, String gender) {
    if (weightKg <= 0 || age <= 0) return null;
    if (age > 10) return null; // usia >10 pakai BMI

    // Berat badan ideal (rata-rata WHO) berdasarkan usia dan jenis kelamin
    final Map<int, Map<String, double>> idealWeight = {
      1:  {'Male': 9.6,  'Female': 8.9},
      2:  {'Male': 12.2, 'Female': 11.5},
      3:  {'Male': 14.3, 'Female': 13.9},
      4:  {'Male': 16.3, 'Female': 16.1},
      5:  {'Male': 18.3, 'Female': 18.2},
      6:  {'Male': 20.5, 'Female': 20.2},
      7:  {'Male': 22.9, 'Female': 22.4},
      8:  {'Male': 25.6, 'Female': 25.0},
      9:  {'Male': 28.6, 'Female': 28.2},
      10: {'Male': 31.9, 'Female': 31.9},
    };

    if (age < 1 || age > 10) return null;
    final double? ideal = idealWeight[age]?[gender];
    if (ideal == null) return null;

    final double ratio = weightKg / ideal;

    // Klasifikasi berdasarkan rasio terhadap berat ideal WHO
    if (ratio < 0.80)  return 'gizi_buruk';   // < 80% berat ideal = gizi buruk
    if (ratio < 0.90)  return 'gizi_kurang';  // 80–90% = gizi kurang
    if (ratio <= 1.20) return 'gizi_baik';    // 90–120% = gizi baik / normal
    if (ratio <= 1.40) return 'gizi_lebih';   // 120–140% = gizi lebih
    return 'obesitas';                        // >140% = obesitas
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
    _heartPollTimer?.cancel();
    _tempPollTimer?.cancel();
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

  /// Pastikan check_id sudah ada sebelum mulai polling.
  /// Jika belum ada, buat sesi baru dari backend agar Flutter tahu check_id
  /// sebelum pengukuran selesai (diperlukan untuk polling chart real-time).
  Future<void> _ensureSession() async {
    if (_checkId != null) return;
    try {
      final newId = await ref.read(apiServiceProvider).createHealthSession();
      if (newId != null && mounted) {
        setState(() => _checkId = newId);
      }
    } catch (_) {
      // Jika gagal, biarkan checkHeartRate/checkBodyTemperature membuat sesi sendiri
    }
  }

  /// Mulai polling data raw detak jantung setiap 2 detik untuk update grafik.
  void _startHeartPoll() {
    _heartPollTimer?.cancel();
    _heartPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || !_loadingHeartRate) {
        timer.cancel();
        return;
      }
      final checkId = _checkId;
      if (checkId == null) return;
      try {
        final data = await ref.read(apiServiceProvider).getRawSensorReadings(
          checkId: checkId,
          type: 'heart_rate',
        );
        if (mounted && data.isNotEmpty) {
          setState(() => _heartChartData = data);
        }
      } catch (_) {}
    });
  }

  void _stopHeartPoll() {
    _heartPollTimer?.cancel();
    _heartPollTimer = null;
  }

  /// Mulai polling data raw suhu tubuh setiap 400ms untuk update grafik.
  void _startTempPoll() {
    _tempPollTimer?.cancel();
    _tempPollTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (!mounted || !_loadingBodyTemp) {
        timer.cancel();
        return;
      }
      final checkId = _checkId;
      if (checkId == null) return;
      try {
        final data = await ref.read(apiServiceProvider).getRawSensorReadings(
          checkId: checkId,
          type: 'body_temp',
        );
        if (mounted && data.isNotEmpty) {
          setState(() => _tempChartData = data);
        }
      } catch (_) {}
    });
  }

  void _stopTempPoll() {
    _tempPollTimer?.cancel();
    _tempPollTimer = null;
  }

  Future<void> _checkHeartRate() async {
    _heartTimer?.cancel();
    setState(() {
      _loadingHeartRate = true;
      _result = null;
      _heartChartData = [];  // Reset chart data setiap pengukuran baru
    });
    _startHeartCountdown();

    // Step 1: Pastikan check_id sudah ada agar bisa mulai poll chart
    await _ensureSession();

    // Step 2: Mulai polling grafik real-time (paralel dengan HTTP request)
    _startHeartPoll();

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
      _stopHeartPoll();
      if (mounted) setState(() { _loadingHeartRate = false; _heartRemainingSeconds = 0; });
    }
  }

  Future<void> _checkBodyTemperature() async {
    _tempTimer?.cancel();
    setState(() {
      _loadingBodyTemp = true;
      _result = null;
      _tempChartData = [];  // Reset chart data setiap pengukuran baru
    });
    _startTempCountdown();

    // Step 1: Pastikan check_id sudah ada
    await _ensureSession();

    // Step 2: Mulai polling grafik real-time
    _startTempPoll();

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
      _stopTempPoll();
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
      // Target update rate: 150ms (respon sangat cepat sesuai Serial Monitor)
      final delay = 150 - elapsed;
      if (delay > 0) {
        await Future.delayed(Duration(milliseconds: delay));
      } else {
        await Future.delayed(const Duration(milliseconds: 20));
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
          // Pertahankan berat badan yang valid (>= 1.0 kg) jika pengguna turun dari timbangan
          if (nextWeight >= 1.0 || _weightKg == null) {
            _weightKg = nextWeight;
          }
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
    // Otomatis matikan mode streaming timbangan saat menekan proses
    if (_isStreamingWeight) {
      _stopWeightStreaming();
    }

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
        weightKg: _weightKg,
        heightCm: _heightCm,
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
            // chartWidget: (_loadingHeartRate || _heartChartData.isNotEmpty)
            //     ? _buildHeartChart()
            //     : null,
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
            // chartWidget: (_loadingBodyTemp || _tempChartData.isNotEmpty)
            //     ? _buildTempChart()
            //     : null,
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
            statusChip: _localHeightStatus(_heightCm) != null
                ? _statusChip(_localHeightStatus(_heightCm)!) : null,
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

  /// Grafik real-time detak jantung (data BPM dari sensor MAX30102).
  Widget _buildHeartChart() {
    const accentColor = Color(0xFFEF4444); // merah
    if (_heartChartData.isEmpty) {
      return _chartPlaceholder(
        accentColor,
        'Menunggu sinyal dari sensor jari (MAX30102)...',
        Icons.favorite_border_rounded,
      );
    }
    final spots = _heartChartData.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minRaw = _heartChartData.reduce((a, b) => a < b ? a : b);
    final maxRaw = _heartChartData.reduce((a, b) => a > b ? a : b);
    final minY   = (minRaw - 10).clamp(30.0, 100.0);
    final maxY   = (maxRaw + 10).clamp(80.0, 180.0);

    return _chartContainer(
      accentColor,
      label: 'BPM (detak jantung live)',
      lastValue: '${_heartChartData.last.toStringAsFixed(1)} bpm',
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0x22FFFFFF), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY, maxY: maxY,
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: 60,  color: const Color(0x8022C55E), strokeWidth: 1, dashArray: [5, 4]),
            HorizontalLine(y: 100, color: const Color(0x80F59E0B), strokeWidth: 1, dashArray: [5, 4]),
          ]),
          lineBarsData: [LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: accentColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [accentColor.withOpacity(0.35), accentColor.withOpacity(0.0)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          )],
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// Grafik real-time suhu tubuh (data °C dari sensor MLX90614).
  Widget _buildTempChart() {
    const accentColor = Color(0xFFF59E0B); // amber
    if (_tempChartData.isEmpty) {
      return _chartPlaceholder(
        accentColor,
        'Menunggu sinyal dari sensor suhu (MLX90614)...',
        Icons.thermostat_rounded,
      );
    }
    final spots = _tempChartData.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minRaw = _tempChartData.reduce((a, b) => a < b ? a : b);
    final maxRaw = _tempChartData.reduce((a, b) => a > b ? a : b);
    final minY   = (minRaw - 0.8).clamp(34.0, 37.0);
    final maxY   = (maxRaw + 0.8).clamp(37.0, 42.0);

    return _chartContainer(
      accentColor,
      label: 'Suhu tubuh live',
      lastValue: '${_tempChartData.last.toStringAsFixed(2)} °C',
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0x22FFFFFF), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
                ),
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: minY, maxY: maxY,
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: 36.4, color: const Color(0x8022C55E), strokeWidth: 1, dashArray: [5, 4]),
            HorizontalLine(y: 37.5, color: const Color(0x80EF4444), strokeWidth: 1, dashArray: [5, 4]),
          ]),
          lineBarsData: [LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.4,
            color: accentColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: _tempChartData.length <= 10,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3, color: accentColor, strokeWidth: 1, strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [accentColor.withOpacity(0.35), accentColor.withOpacity(0.0)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          )],
          lineTouchData: const LineTouchData(enabled: false),
        ),
        duration: const Duration(milliseconds: 200),
      ),
    );
  }

  /// Wrapper container berwarna gelap untuk grafik dengan label dan nilai terakhir.
  Widget _chartContainer(Color accent, {required String label, required String lastValue, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(color: accent.withOpacity(0.85), fontSize: 10, fontWeight: FontWeight.w600)),
          Text(lastValue, style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Expanded(child: child),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Normal (hijau)', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 8)),
          Text('Batas atas (kuning)', style: TextStyle(color: const Color(0xFFF59E0B).withOpacity(0.8), fontSize: 8)),
        ]),
      ]),
    );
  }

  /// Placeholder chart saat menunggu data pertama dari sensor.
  Widget _chartPlaceholder(Color accent, String msg, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: accent.withOpacity(0.4), size: 28),
        const SizedBox(height: 8),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: accent.withOpacity(0.6), fontSize: 11),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 60,
          child: LinearProgressIndicator(
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(accent.withOpacity(0.6)),
          ),
        ),
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
    Widget? chartWidget,   // <<< grafik real-time (opsional)
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
        // ── Grafik real-time sensor (muncul saat loading atau data sudah ada) ──
        if (chartWidget != null) ...[
          const SizedBox(height: 12),
          chartWidget,
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

    // Format tanggal dari checkedAtIso
    final DateTime checkedAt = DateTime.tryParse(r.checkedAtIso) ?? DateTime.now();
    final String dateStr =
        '${checkedAt.day.toString().padLeft(2, '0')}-'
        '${checkedAt.month.toString().padLeft(2, '0')}-'
        '${checkedAt.year}';

    // Status tinggi badan (dihitung lokal karena server tidak mengembalikannya)
    final String? heightStatus = _localHeightStatus(r.heightCm);

    // Status berat badan:
    // - Usia 1-10 tahun : pakai BB/U standar WHO
    // - Usia >10 tahun  : pakai bmiStatus dari server
    final String? weightStatusLocal = _localWeightStatus(r.weightKg, r.age, r.gender);
    final String? weightStatus = weightStatusLocal ?? r.bmiStatus;

    // Warna & label final result
    final Color finalColor  = isNormal ? const Color(0xFF0D9F6E) : const Color(0xFFF59E0B);
    final String finalLabel = isNormal ? '🟢 NORMAL' : '🟡 PERLU PERHATIAN';

    // Pesan rekomendasi - dibuat otomatis berdasarkan parameter yang bermasalah
    final List<String> adviceList = [];

    // ── Detak jantung ──
    final String hr = r.heartStatus.toLowerCase();
    if (hr == 'rendah') {
      adviceList.add('❤️ Detak jantung rendah - Istirahat yang cukup, hindari aktivitas berat tiba-tiba, dan pastikan hidrasi tubuh.');
    } else if (hr == 'tinggi' || hr == 'perlu_perhatian') {
      adviceList.add('❤️ Detak jantung tinggi - Tenangkan diri, tarik napas dalam-dalam, kurangi kafein, dan hindari stres berlebihan.');
    }

    // ── Suhu tubuh ──
    final String tmp = r.tempStatus.toLowerCase();
    if (tmp == 'rendah') {
      adviceList.add('🌡️ Suhu tubuh rendah - Kenakan pakaian hangat, konsumsi minuman hangat, dan istirahat di tempat yang nyaman.');
    } else if (tmp == 'hangat') {
      adviceList.add('🌡️ Suhu tubuh hangat - Minum air putih yang cukup dan istirahat sebentar.');
    } else if (tmp == 'demam' || tmp == 'perlu_perhatian') {
      adviceList.add('🌡️ Demam - Minum paracetamol jika perlu, banyak minum air, kompres dahi, dan segera konsultasi dokter jika suhu di atas 39°C.');
    }

    // ── Tinggi badan ──
    final String? hs = heightStatus;
    if (hs == 'pendek') {
      adviceList.add('📏 Tinggi badan pendek - Perhatikan asupan nutrisi terutama protein, kalsium, dan vitamin D. Konsultasikan ke dokter anak atau ahli gizi.');
    } else if (hs == 'sangat_pendek') {
      adviceList.add('📏 Sangat pendek (potensi stunting) - Segera konsultasikan ke dokter atau puskesmas untuk evaluasi pertumbuhan lebih lanjut.');
    }

    // ── Berat badan ──
    // Usia 1-10: gunakan status BB/U (gizi buruk/kurang/baik/lebih)
    // Usia >10 : gunakan BMI
    if (r.age <= 10 && weightStatusLocal != null) {
      if (weightStatusLocal == 'gizi_buruk') {
        adviceList.add('⚖️ Gizi buruk - Segera konsultasikan ke dokter atau puskesmas. Anak membutuhkan penanganan gizi intensif secepatnya.');
      } else if (weightStatusLocal == 'gizi_kurang') {
        adviceList.add('⚖️ Gizi kurang - Perbanyak asupan protein (telur, ikan, daging), karbohidrat kompleks, dan lemak sehat. Makan 3x sehari + 2 camilan bergizi.');
      } else if (weightStatusLocal == 'gizi_lebih') {
        adviceList.add('⚖️ Berat badan berlebih - Kurangi makanan tinggi gula & lemak jenuh. Perbanyak sayur, buah, dan ajak anak aktif bergerak minimal 60 menit/hari.');
      } else if (weightStatusLocal == 'obesitas') {
        adviceList.add('⚖️ Obesitas - Konsultasikan ke dokter anak atau ahli gizi untuk program pengelolaan berat badan yang aman sesuai usianya.');
      }
    } else {
      final String bmi = r.bmiStatus.toLowerCase();
      if (bmi == 'kurus' || bmi == 'underweight') {
        adviceList.add('⚖️ Berat badan kurang - Perbanyak asupan kalori bergizi (protein, karbohidrat kompleks), makan 3x sehari + 2 camilan sehat.');
      } else if (bmi == 'gemuk' || bmi == 'pre_obese') {
        adviceList.add('⚖️ Berat badan berlebih - Kurangi makanan tinggi gula & lemak jenuh, perbanyak sayur, buah, dan olahraga minimal 30 menit/hari.');
      } else if (bmi.startsWith('obese') || bmi == 'obesitas') {
        adviceList.add('⚖️ Obesitas - Disarankan berkonsultasi dengan dokter atau ahli gizi untuk program penurunan berat badan yang aman dan terstruktur.');
      }
    }

    // ── Jika semua normal ──
    if (adviceList.isEmpty) {
      adviceList.add('✅ Semua parameter dalam batas normal. Pertahankan pola makan sehat, olahraga rutin, dan tidur yang cukup!');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        // ══ HEADER ══════════════════════════════════════════
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: const Column(children: [
            Text('SMART SNACK BOX', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2.5)),
            SizedBox(height: 4),
            Text('HEALTH REPORT', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ]),
        ),

        // ══ DIVIDER ══════════════════════════════════════════
        _reportDivider(),

        // ── Tanggal ─────────────────────────────────────────
        _reportDateRow(dateStr),
        _reportDivider(),

        // ── Heart Rate ──────────────────────────────────────
        _reportMetricRow(
          emoji: '❤️',
          label: 'Heart Rate',
          value: '${r.heartRate.toStringAsFixed(0)} bpm',
          status: r.heartStatus,
        ),
        _reportDivider(),

        // ── Suhu Tubuh ──────────────────────────────────────
        _reportMetricRow(
          emoji: '🌡️',
          label: 'Body Temperature',
          value: '${r.bodyTemp.toStringAsFixed(1)}°C',
          status: r.tempStatus,
        ),
        _reportDivider(),

        // ── Tinggi Badan ─────────────────────────────────────
        _reportMetricRow(
          emoji: '📏',
          label: 'Height',
          value: '${r.heightCm.toStringAsFixed(1)} cm',
          status: heightStatus,
        ),
        _reportDivider(),

        // ── Berat Badan ─────────────────────────────────────
        _reportMetricRow(
          emoji: '⚖️',
          label: 'Weight',
          value: '${r.weightKg.toStringAsFixed(1)} kg',
          // Usia 1-10: status BB/U WHO | Usia >10: status BMI
          status: weightStatus,
        ),
        _reportDivider(),

        // ── BMI ─────────────────────────────────────────────
        _reportMetricRow(
          emoji: '🧮',
          label: 'BMI',
          value: r.bmi.toStringAsFixed(2),
          status: r.bmiStatus,
        ),
        _reportDivider(),

        // ══ FINAL RESULT ═════════════════════════════════════
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Text('📋', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Text('Final Result', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              decoration: BoxDecoration(
                color: finalColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: finalColor.withOpacity(0.35), width: 1.5),
              ),
              child: Text(
                finalLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: finalColor, letterSpacing: 0.8),
              ),
            ),
            const SizedBox(height: 12),

            // Advice / recommendation - satu item per masalah
            Column(
              children: adviceList.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('💡', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF374151), height: 1.55),
                    ),
                  ),
                ]),
              )).toList(),
            ),
          ]),
        ),

        // ── Kotak snack info ────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isNormal
                    ? [const Color(0xFF0D9F6E), const Color(0xFF059669)]
                    : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Text(isNormal ? '🎁' : '💪', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    isNormal ? 'Kotak Snack Terbuka!' : 'Tetap Semangat!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isNormal
                        ? 'Ambil snack kamu dalam 10 detik. Kotak menutup otomatis.'
                        : 'Kotak snack tetap terbuka. Jaga pola makan & hidrasi ya!',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                  ),
                ]),
              ),
            ]),
          ),
        ),

      ]),
    );
  }

  /// Satu baris divider bergaya "report" dengan dashes
  Widget _reportDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, thickness: 1, color: const Color(0xFFE5E7EB)),
    );
  }

  /// Baris tanggal di report
  Widget _reportDateRow(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Tanggal', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
        Text(date, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
      ]),
    );
  }

  /// Satu blok metrik dalam report card
  Widget _reportMetricRow({
    required String emoji,
    required String label,
    required String value,
    required String? status,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Label baris atas
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
        ]),
        const SizedBox(height: 8),
        // Nilai + Status dalam satu baris
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF111827), letterSpacing: -0.5)),
          if (status != null)
            Row(children: [
              const Text('Status', style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
              const SizedBox(width: 8),
              _statusChip(status),
            ]),
        ]),
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
      // ── Status tinggi badan (WHO/Kemenkes RI) ──
      case 'pendek':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Pendek';
        icon = Icons.warning_rounded;
        break;
      case 'sangat_pendek':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF7F1D1D);
        label = 'Sangat Pendek';
        icon = Icons.error_rounded;
        break;
      // ── Status berat badan BB/U (WHO, usia 1-10 tahun) ──
      case 'gizi_baik':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        label = 'Gizi Baik';
        icon = Icons.check_circle_rounded;
        break;
      case 'gizi_kurang':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Gizi Kurang';
        icon = Icons.warning_rounded;
        break;
      case 'gizi_buruk':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF7F1D1D);
        label = 'Gizi Buruk';
        icon = Icons.error_rounded;
        break;
      case 'gizi_lebih':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF78350F);
        label = 'Gizi Lebih';
        icon = Icons.warning_rounded;
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
