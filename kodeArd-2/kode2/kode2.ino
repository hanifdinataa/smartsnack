#include <Wire.h>               // Library untuk komunikasi I2C (digunakan oleh sensor MAX30102 & MLX90614)
#include <WiFi.h>               // Library untuk menghubungkan ESP32 ke jaringan Wi-Fi
#include <PubSubClient.h>         // Library untuk protokol komunikasi MQTT (PubSub Client)
#include <ESP32Servo.h>          // Library untuk mengontrol Motor Servo pada ESP32
#include <math.h>               // Library fungsi matematika (misalnya fabsf untuk hitung selisih mutlak)
#include "MAX30105.h"           // Library sensor detak jantung & pulsa IR/Red (MAX30102/MAX30105)
#include "heartRate.h"          // Library pendeteksi puncak gelombang detak jantung (checkForBeat)
#include <Adafruit_MLX90614.h>  // Library sensor suhu tubuh non-kontak (MLX90614)

// ===== OBJEK SENSOR & KONEKSI =====
MAX30105 particleSensor;        // Objek untuk mengakses sensor MAX30102
Adafruit_MLX90614 mlx = Adafruit_MLX90614(); // Objek untuk mengakses sensor suhu MLX90614

WiFiClient espClient;           // Klien TCP Wi-Fi ESP32
PubSubClient mqtt(espClient);   // Klien MQTT yang menggunakan koneksi Wi-Fi espClient
Servo snackServo;               // Objek pengontrol Motor Servo untuk buka/tutup pintu snack box

// ===== KONFIGURASI JARINGAN WIFI & BROKER MQTT =====
const char* WIFI_SSID = "RUMAHMU";      // Nama Wi-Fi (SSID) yang dihubungkan
const char* WIFI_PASS = "zzzzzzzz";     // Password Wi-Fi

const char* MQTT_HOST = "54.144.6.206"; // IP Public / Hostname Broker MQTT EC2
const int   MQTT_PORT = 1884;           // Port Broker MQTT
const char* MQTT_USER = "";             // Username MQTT (kosongkan jika tanpa autentikasi)
const char* MQTT_PASS = "";             // Password MQTT
const char* DEVICE_ID = "esp32_health_01"; // ID Unik Perangkat ESP32 ini

// Variable penyimpan nama Topik MQTT
String commandTopic;     // Topik untuk menerima perintah ukur dari Backend (smartsnack/health/command/esp32_health_01)
String resultTopic;      // Topik untuk mengirim hasil pengukuran ke Backend (smartsnack/health/result/esp32_health_01)
String rawTopic;         // Topik untuk mengirim data mentah sensor secara real-time (grafik Flutter) (smartsnack/health/raw/esp32_health_01)
String boxEventTopic;    // Topik untuk mengirim event tombol ditekan ke Backend (smartsnack/box/event/esp32_health_01)
String boxDecisionTopic; // Topik untuk menerima keputusan buka kotak dari Backend (smartsnack/box/decision/esp32_health_01)

// ===== KONSTANTA HARDWARE & PARAMETER WAKTU =====
const unsigned long HEART_DURATION_MS           = 60000;  // Durasi total pengukuran detak jantung (60 detik / 1 menit)
const int           TEMP_SAMPLES                = 25;     // Jumlah total sampel pembacaan suhu tubuh
const int           TEMP_WARMUP_SAMPLES         = 5;      // Jumlah sampel stabilisasi awal (warmup) sensor suhu
const unsigned long TEMP_SAMPLE_DELAY_MS        = 120;    // Jeda antar sampel suhu (120 milidetik)
const float         TEMP_CALIBRATION_OFFSET_C   = 0.3f;   // Nilai offset kalibrasi suhu (+0.3 derajat Celsius)
const float         TEMP_MAX_DEVIATION_FROM_MEDIAN_C = 1.2f; // Batas maksimal toleransi deviasi suhu dari median (1.2 C)
const long          FINGER_IR_THRESHOLD         = 8000;   // Nilai ambang batas infra-merah (IR) untuk mendeteksi keberadaan jari
const unsigned long FINGER_WAIT_TIMEOUT_MS      = 45000;  // Waktu maksimal menunggu jari ditempelkan (45 detik)
const int           SERVO_PIN                   = 18;     // Pin GPIO tempat kabel sinyal servo terhubung (Pin 18)
const int           BUTTON_PIN                  = 15;     // Pin GPIO tempat tombol fisik terhubung (Pin 15)
const int           SERVO_CLOSED_ANGLE          = 0;      // Sudut rotasi servo saat posisi kotak TUTUP (0 derajat)
const int           SERVO_OPEN_ANGLE            = 45;     // Sudut rotasi servo saat posisi kotak BUKA (45 derajat)
const int           BUTTON_ACTIVE_STATE         = LOW;    // Status tombol saat ditekan (LOW karena menggunakan INPUT_PULLUP)
const unsigned long BUTTON_DEBOUNCE_MS          = 120;    // Waktu penstabilan getaran tombol / debounce (120 ms)
const unsigned long BUTTON_COOLDOWN_MS          = 1000;   // Waktu jeda antartekanan tombol / cooldown (1 detik)
const unsigned long BOX_DECISION_TIMEOUT_MS     = 20000;  // Waktu maksimal menunggu keputusan buka kotak dari backend (20 detik)
const int           BOX_DECISION_MAX_RETRY      = 2;      // Jumlah percobaan ulang (retry) jika backend belum membalas
const bool          ENABLE_SERVO_BOOT_TEST      = true;   // Sakelar tes buka-tutup servo otomatis saat awal booting
const int           BUZZER_PIN                  = 4;      // Pin GPIO untuk Active Buzzer (Pin 4)

// ===== STATE VARIABLES (VARIABEL STATUS RUNTIME) =====
unsigned long lastMqttReconnectMs     = 0; // Waktu terakhir mencoba menghubungkan ulang ke MQTT broker
unsigned long lastMqttLoopKickMs      = 0; // Waktu terakhir log status MQTT aktif dicetak
unsigned long lastButtonEdgeMs        = 0; // Waktu perubahan posisi fisik tombol (untuk debounce)
unsigned long lastButtonPublishMs     = 0; // Waktu terakhir event tombol dikirim ke MQTT
unsigned long buttonDecisionRequestedAt = 0; // Waktu saat tombol ditekan & menunggu balasan backend
bool          lastButtonReading       = HIGH; // Pembacaan terakhir nilai fisik tombol
bool          buttonPressLatched      = false;// Penanda bahwa penekanan tombol sudah diproses (mencegah double trigger)
bool          waitingBoxDecision      = false;// Penanda apakah ESP32 sedang dalam status menunggu balasan dari backend
int           boxDecisionRetryCount   = 0;    // Penghitung jumlah retry pengiriman tombol
bool          servoIsOpen             = false;// Penanda status kondisi servo (true = Buka, false = Tutup)
unsigned long servoOpenedAtMs         = 0;    // Waktu (timestamp) saat servo mulai dibuka
unsigned long servoAutoCloseMs        = 6000; // Durasi lamanya servo terbuka sebelum otomatis menutup (6000 ms = 6 detik)
unsigned long lastNetworkDiagMs       = 0;    // Waktu terakhir diagnosa jaringan dicetak
unsigned long lastWifiRetryMs         = 0;    // Waktu terakhir mencoba reconnect Wi-Fi
bool          mlxReady                = false;// Penanda apakah sensor suhu MLX90614 berhasil diinisialisasi
float         lastGoodBodyTempC       = NAN;  // Nilai cache suhu terakhir yang valid
unsigned long lastGoodBodyTempMs      = 0;    // Waktu (timestamp) saat suhu cache tersebut diambil
const unsigned long TEMP_CACHE_TTL_MS = 10UL * 60UL * 1000UL; // Masa berlaku cache suhu (10 menit)

// ========== FORWARD DECLARATIONS (DEKLARASI FUNGSI AWAL) ==========
void connectMqtt();
void connectWifi();
float measureHeartRateBpm(String& errorCode, const String& checkId);
float measureBodyTemperatureC(String& errorCode, const String& checkId);

// ========== DIAGNOSTIC HELPERS (PEMBANTU LOGGING SERIAL) ==========
// Fungsi mencetak garis pemisah di Serial Monitor
void printSeparator() {
  Serial.println("----------------------------------------");
}

// Fungsi memindai alamat I2C untuk mengecek koneksi fisik sensor (0x57 untuk MAX30102, 0x5A untuk MLX90614)
void scanI2cBus() {
  Serial.println("[I2C] Scanning bus...");
  int found = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    uint8_t err = Wire.endTransmission();
    if (err == 0) {
      Serial.print("[I2C] Found device at 0x");
      if (addr < 16) Serial.print("0");
      Serial.println(addr, HEX);
      found++;
    }
  }
  if (found == 0) Serial.println("[I2C] Tidak ada device terdeteksi.");
}

// Fungsi menguji apakah port TCP broker MQTT dapat dijangkau
bool testBrokerTcpReachable() {
  WiFiClient tester;
  bool ok = tester.connect(MQTT_HOST, MQTT_PORT);
  tester.stop();
  return ok;
}

// Fungsi mencetak diagnosa singkat status koneksi Wi-Fi & Broker di Serial Monitor
void logNetworkDiag() {
  printSeparator();
  Serial.print("WiFi           : ");
  Serial.println(WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
  bool tcpOk = testBrokerTcpReachable();
  Serial.print("Broker         : ");
  Serial.println(tcpOk ? "CONNECTED" : "DISCONNECTED");
  printSeparator();
}

// ========== JSON HELPERS (PEMBANTU PARSING DATA JSON) ==========
// Fungsi menambahkan backslash pada karakter khusus agar format JSON valid
String jsonEscape(const String& input) {
  String out = "";
  for (size_t i = 0; i < input.length(); i++) {
    char c = input.charAt(i);
    if (c == '\"' || c == '\\') { out += '\\'; out += c; }
    else if (c == '\n') out += "\\n";
    else out += c;
  }
  return out;
}

// Fungsi mengekstrak nilai string dari kunci JSON tertentu tanpa library berat
String extractJsonValue(const String& payload, const String& key) {
  String token = "\"" + key + "\"";
  int keyPos = payload.indexOf(token);
  if (keyPos < 0) return "";
  int colonPos = payload.indexOf(':', keyPos + token.length());
  if (colonPos < 0) return "";
  int start = colonPos + 1;
  while (start < (int)payload.length() && (payload[start] == ' ' || payload[start] == '\t')) start++;
  if (start >= (int)payload.length()) return "";
  if (payload[start] == '\"') {
    int end = payload.indexOf('\"', start + 1);
    if (end < 0) return "";
    return payload.substring(start + 1, end);
  }
  int end = start;
  while (end < (int)payload.length() &&
         payload[end] != ',' && payload[end] != '}' && payload[end] != '\n') end++;
  return payload.substring(start, end);
}

// ========== BUZZER (PENGONTROL BUNYI BUZZER) ==========
// Fungsi membunyikan buzzer selama durasi tertentu (default 1000 ms = 1 detik)
void beepBuzzer(unsigned long durationMs = 1000) {
  digitalWrite(BUZZER_PIN, HIGH); // Nyalakan buzzer
  delay(durationMs);              // Tahan bunyi
  digitalWrite(BUZZER_PIN, LOW);  // Matikan buzzer
}

// ========== SENSOR INIT (INISIALISASI SENSOR) ==========
// Fungsi memastikan sensor MAX30102 siap & mengatur kecepatan clock bus I2C ke 100kHz
bool ensureMax30102Ready() {
  Wire.setClock(100000); // Naikkan clock I2C ke 100kHz untuk MAX30102
  delay(50);
  if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x1F); // Amplitudo LED Merah
    particleSensor.setPulseAmplitudeIR(0x24);  // Amplitudo LED Infra-Merah
    return true;
  }
  return false;
}

// Fungsi pemulihan (recovery) sensor suhu MLX90614 jika terjadi kegagalan komunikasi I2C
bool ensureMlxReady() {
  if (mlxReady) return true;

  Serial.println("[TEMP] Mencoba recovery MLX90614...");
  const uint32_t clockSpeeds[] = {50000, 25000, 10000};

  for (int s = 0; s < 3; s++) {
    Wire.end();
    delay(150);
    Wire.begin(21, 22);
    Wire.setClock(clockSpeeds[s]); // Turunkan clock I2C agar MLX90614 lebih stabil
    delay(500);

    Serial.print("[TEMP] Coba clock speed: "); Serial.println(clockSpeeds[s]);
    scanI2cBus();

    for (int attempt = 1; attempt <= 3; attempt++) {
      Serial.print("[TEMP] Coba init MLX90614 ke-"); Serial.print(attempt);
      Serial.print(" (clock="); Serial.print(clockSpeeds[s]); Serial.println(")");

      if (mlx.begin()) {
        mlxReady = true;
        Serial.println("[TEMP] MLX90614 recovery berhasil!");
        Wire.setClock(100000); // Kembalikan ke 100kHz
        return true;
      }
      delay(500);
    }
  }

  Serial.println("[TEMP] MLX90614 recovery gagal semua clock speed.");
  Wire.setClock(100000);
  return false;
}

// ========== HEART RATE (PENGUKURAN DETAK JANTUNG) ==========
// Fungsi utama untuk mengukur detak jantung (BPM) menggunakan sensor MAX30102
// checkId diteruskan untuk dikirim bersama data raw ke topic grafik Flutter
float measureHeartRateBpm(String& errorCode, const String& checkId) {
  // 1. Pastikan sensor MAX30102 siap diakses
  if (!ensureMax30102Ready()) {
    Serial.println("[HR] Pengukuran selesai.");
    errorCode = "sensor_unavailable";
    return 0.0f;
  }

  const int MAX_RATE_SAMPLES = 180;
  float rates[MAX_RATE_SAMPLES]; // Array penampung nilai BPM tiap denyut
  int   validRates    = 0;       // Jumlah sampel BPM valid yang terkumpul
  long  lastBeatMs    = 0;       // Waktu (timestamp) puncak denyut sebelumnya
  int   fingerSamples = 0;       // Jumlah sampel sinyal IR yang terbaca
  const unsigned long WARMUP_MS = 8000; // 8 detik pertama diabaikan (warmup posisi jari)

  Serial.println();
  Serial.println("====================================================");
  Serial.println("        PEMBACAAN DETAK JANTUNG (MAX30102)");
  Serial.println("====================================================");
  Serial.println("Memulai pembacaan detak jantung...");
  Serial.print("Silakan letakkan jari pada sensor.");

  // 2. Kalibrasi ambang batas IR adaptif sesuai pantulan jari pengguna
  long baselineTotal = 0;
  const int BASELINE_SAMPLES = 40;
  for (int i = 0; i < BASELINE_SAMPLES; i++) {
    baselineTotal += particleSensor.getIR();
    delay(8);
  }
  long irBaseline       = baselineTotal / BASELINE_SAMPLES;
  long adaptiveThreshold = irBaseline + 2500;
  if (adaptiveThreshold < FINGER_IR_THRESHOLD) adaptiveThreshold = FINGER_IR_THRESHOLD;
  if (adaptiveThreshold > 25000)               adaptiveThreshold = 25000;

  // 3. Loop menunggu keberadaan jari menempel pada sensor (maksimal 45 detik)
  unsigned long fingerWaitStart  = millis();
  bool          fingerDetected   = false;
  int           consecutiveDetected = 0;

  while (millis() - fingerWaitStart < FINGER_WAIT_TIMEOUT_MS) {
    if (mqtt.connected()) mqtt.loop();
    long irValue = particleSensor.getIR();

    static unsigned long lastIrPrint = 0;
    if (millis() - lastIrPrint > 1000) {
      Serial.print(".");
      lastIrPrint = millis();
    }

    // Jari terdeteksi jika nilai IR melebihi ambang batas secara konsisten
    if (irValue > adaptiveThreshold) {
      consecutiveDetected++;
      if (consecutiveDetected >= 8) {
        fingerDetected = true;
        Serial.println();
        Serial.println("Jari berhasil terdeteksi.");
        break;
      }
    } else {
      consecutiveDetected = 0;
    }
    delay(20);
  }

  // Jika jari tidak ditempelkan dalam 45 detik, kembalikan error
  if (!fingerDetected) {
    Serial.println();
    Serial.println("GAGAL - Jari tidak terdeteksi dalam batas waktu.");
    errorCode = "finger_not_detected";
    return 0.0f;
  }

  // 4. Loop utama pengambilan sampel detak jantung selama 60 detik (HEART_DURATION_MS)
  unsigned long startTime       = millis();
  int           beatCount       = 0;
  unsigned long lastProgressPrint = 0;
  int           lastProgressPct  = -1;

  // Variabel untuk tracking waktu publish raw data (setiap 2 detik)
  unsigned long lastRawPublish   = 0;
  float         liveRateTotal    = 0.0f;
  int           liveRateCount    = 0;

  Serial.println("Progress Pengukuran");

  while (millis() - startTime < HEART_DURATION_MS) {
    if (mqtt.connected()) mqtt.loop();
    else connectMqtt();

    long irValue = particleSensor.getIR();
    if (irValue > adaptiveThreshold) {
      fingerSamples++;
      // Deteksi puncak gelombang denyut nadi
      if (checkForBeat(irValue)) {
        long nowMs = millis();
        if (lastBeatMs > 0) {
          long delta = nowMs - lastBeatMs; // Jeda waktu antar dua denyut dalam milidetik
          if (delta > 0) {
            float bpm = 60.0f / (delta / 1000.0f); // Rumus konversi jeda waktu ke nilai BPM (Beats Per Minute)
            
            // HANYA simpan data jika waktu > 8 detik (lewat warmup) & angka BPM logis (40 - 180)
            if ((millis() - startTime) > WARMUP_MS && bpm >= 40.0f && bpm <= 180.0f) {
              if (validRates < MAX_RATE_SAMPLES) rates[validRates++] = bpm;
              beatCount++;
              // Akumulasi untuk rata-rata live (grafik real-time)
              liveRateTotal += bpm;
              liveRateCount++;
            }
          }
        }
        lastBeatMs = nowMs;
      }
    }

    // ── Publish data mentah ke rawTopic setiap 2 detik (untuk grafik Flutter) ──
    if (millis() - lastRawPublish >= 2000) {
      lastRawPublish = millis();
      float liveBpm = (liveRateCount > 0) ? (liveRateTotal / liveRateCount) : 0.0f;
      bool  fingerOn = (irValue > adaptiveThreshold);
      String rawPayload = "{";
      rawPayload += "\"action\":\"heart_rate_raw\",";
      rawPayload += "\"check_id\":" + checkId + ",";
      rawPayload += "\"bpm\":" + String(liveBpm, 1) + ",";
      rawPayload += "\"ir\":" + String(irValue) + ",";
      rawPayload += "\"finger_on\":" + String(fingerOn ? "true" : "false") + ",";
      rawPayload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
      rawPayload += "}";
      if (mqtt.connected()) {
        mqtt.publish(rawTopic.c_str(), rawPayload.c_str());
      }
    }

    // Tampilkan indikator progress persentase di Serial Monitor
    unsigned long elapsed = (millis() - startTime) / 1000;
    int pct = (int)(elapsed * 100 / 60);
    if (pct > 100) pct = 100;
    if (pct / 25 != lastProgressPct / 25 && pct % 25 == 0 && pct != lastProgressPct) {
      lastProgressPct = pct;
      int filled = pct / 5;
      Serial.print("[");
      for (int p = 0; p < 20; p++) Serial.print(p < filled ? "#" : "-");
      Serial.print("] ");
      if (pct < 100) Serial.print(" ");
      Serial.print(pct); Serial.println("%");
    }
    delay(10);
  }

  // Jika sampel kurang banyak (terlalu banyak gerakan/terlepas), anggap gagal
  if (fingerSamples < 100 || validRates < 12) {
    Serial.println("GAGAL - Sinyal tidak valid (kurang sampel).");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  // 5. Algoritma Pengurutan (Bubble Sort) untuk mencari nilai tengah (Median)
  float sorted[MAX_RATE_SAMPLES];
  for (int i = 0; i < validRates; i++) sorted[i] = rates[i];
  for (int i = 0; i < validRates - 1; i++) {
    for (int j = i + 1; j < validRates; j++) {
      if (sorted[j] < sorted[i]) { float tmp = sorted[i]; sorted[i] = sorted[j]; sorted[j] = tmp; }
    }
  }
  float median = sorted[validRates / 2]; // Ambil nilai paling tengah (Median)

  // 6. Pemfilteran Outlier: HANYA gunakan data yang selisihnya <= 15 BPM dari nilai Median
  float total = 0.0f;
  int   used  = 0;
  for (int i = 0; i < validRates; i++) {
    if (fabsf(rates[i] - median) <= 15.0f) { total += rates[i]; used++; }
  }

  if (used < 8) {
    Serial.println("GAGAL - Sampel outlier terlalu banyak.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  // 7. Hitung rata-rata akhir BPM dari sampel bersih
  float avgBpm = total / used;
  if (avgBpm < 45.0f || avgBpm > 180.0f) {
    Serial.println("GAGAL - Hasil BPM di luar rentang normal.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  Serial.println();
  Serial.println("Pengukuran selesai.");
  Serial.println("=================== HASIL ===================");
  Serial.print("Detak Jantung : "); Serial.print(avgBpm, 2); Serial.println(" BPM");
  Serial.println("=============================================");

  return avgBpm;
}

// ========== BODY TEMPERATURE (PENGUKURAN SUHU TUBUH) ==========
// Fungsi utama untuk mengukur suhu tubuh (°C) menggunakan sensor non-kontak MLX90614
// checkId diteruskan untuk dikirim bersama data raw ke topic grafik Flutter
float measureBodyTemperatureC(String& errorCode, const String& checkId) {
  // 1. Pastikan sensor MLX90614 siap diakses
  if (!ensureMlxReady()) {
    if (!isnan(lastGoodBodyTempC) && (millis() - lastGoodBodyTempMs) <= TEMP_CACHE_TTL_MS) {
      Serial.println("[TEMP] MLX90614 belum siap, pakai cache suhu terakhir.");
      return lastGoodBodyTempC;
    }
    Serial.println("GAGAL - MLX90614 belum siap.");
    errorCode = "sensor_unavailable";
    return 0.0f;
  }

  Serial.println();
  Serial.println("====================================================");
  Serial.println("        PENGUKURAN SUHU TUBUH (MLX90614)");
  Serial.println("====================================================");
  Serial.println("Memulai pengukuran suhu tubuh...");
  Serial.println("Silakan arahkan sensor ke dahi.");

  // 2. Pembacaan warmup (5 sampel) untuk menstabilkan pembacaan infra-merah suhu
  for (int i = 0; i < TEMP_WARMUP_SAMPLES; i++) {
    if (mqtt.connected()) mqtt.loop();
    else connectMqtt();

    float warmObj = mlx.readObjectTempC(); // Suhu objek (dahi)
    float warmAmb = mlx.readAmbientTempC();// Suhu ruangan (ambient)

    if (isnan(warmObj) && isnan(warmAmb)) {
      if (!isnan(lastGoodBodyTempC) && (millis() - lastGoodBodyTempMs) <= TEMP_CACHE_TTL_MS) {
        Serial.println("[TEMP] Warmup gagal, pakai cache suhu terakhir.");
        return lastGoodBodyTempC;
      }
      Serial.println("GAGAL - Sensor tidak merespons saat warmup.");
      mlxReady = false;
      errorCode = "sensor_unavailable";
      return 0.0f;
    }

    delay(TEMP_SAMPLE_DELAY_MS);
  }

  Serial.println("Objek berhasil terdeteksi.");

  // 3. Ambil 25 sampel pembacaan suhu tubuh
  float readings[TEMP_SAMPLES];
  int   count = 0;

  Serial.println("Progress Pengukuran");

  for (int i = 0; i < TEMP_SAMPLES; i++) {
    if (mqtt.connected()) mqtt.loop();
    else connectMqtt();

    float obj = mlx.readObjectTempC();
    float amb = mlx.readAmbientTempC();

    if (isnan(obj) && isnan(amb)) {
      if (!isnan(lastGoodBodyTempC) && (millis() - lastGoodBodyTempMs) <= TEMP_CACHE_TTL_MS) {
        Serial.println("[TEMP] Disconnect saat sampling, pakai cache suhu terakhir.");
        return lastGoodBodyTempC;
      }
      Serial.println("GAGAL - Sensor disconnect saat sampling! Abort.");
      mlxReady = false;
      errorCode = "sensor_unavailable";
      return 0.0f;
    }

    float t = !isnan(obj) ? obj : amb;
    if (isnan(t) || t < 20.0f || t > 50.0f) {
      continue;
    }

    readings[count++] = t;

    // ── Publish data mentah suhu ke rawTopic setiap sampel (untuk grafik Flutter) ──
    float calibratedT = t + TEMP_CALIBRATION_OFFSET_C;
    String rawPayload = "{";
    rawPayload += "\"action\":\"body_temp_raw\",";
    rawPayload += "\"check_id\":" + checkId + ",";
    rawPayload += "\"temp\":" + String(calibratedT, 2) + ",";
    rawPayload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
    rawPayload += "}";
    if (mqtt.connected()) {
      mqtt.publish(rawTopic.c_str(), rawPayload.c_str());
    }

    // Cetak progress bar persentase di Serial Monitor
    int pct = (int)((i + 1) * 100 / TEMP_SAMPLES);
    if ((i + 1) % (TEMP_SAMPLES / 5) == 0) {
      int filled = pct / 5;
      Serial.print("[");
      for (int p = 0; p < 20; p++) Serial.print(p < filled ? "#" : "-");
      Serial.print("] ");
      if (pct < 100) Serial.print(" ");
      Serial.print(pct); Serial.println("%");
    }

    delay(TEMP_SAMPLE_DELAY_MS);
  }

  if (count < 8) {
    Serial.println("GAGAL - Sampel valid terlalu sedikit.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  // 4. Cari nilai Median suhu tubuh dari 25 sampel
  for (int i = 0; i < count - 1; i++) {
    for (int j = i + 1; j < count; j++) {
      if (readings[j] < readings[i]) { float tmp = readings[i]; readings[i] = readings[j]; readings[j] = tmp; }
    }
  }

  float median = readings[count / 2]; // Nilai median suhu
  float total  = 0.0f;
  int   used   = 0;
  
  // 5. Filter outlier suhu yang selisihnya > 1.2 derajat C dari median
  for (int i = 0; i < count; i++) {
    if (fabsf(readings[i] - median) <= TEMP_MAX_DEVIATION_FROM_MEDIAN_C) { total += readings[i]; used++; }
  }

  if (used < 5) {
    Serial.println("GAGAL - Tidak cukup sampel valid.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  // 6. Rata-rata & Tambahkan Kalibrasi Offset (+0.3 C)
  float avg        = total / used;
  float calibrated = avg + TEMP_CALIBRATION_OFFSET_C;
  lastGoodBodyTempC = calibrated; // Simpan ke cache
  lastGoodBodyTempMs = millis();

  Serial.println("Pengukuran selesai.");
  Serial.println("=================== HASIL ===================");
  Serial.print("Suhu Terukur : "); Serial.print(calibrated, 2); Serial.println(" \xB0C");
  Serial.println("=============================================");

  return calibrated;
}

// ========== PUBLISH FUNCTIONS (FUNGSI PUBLIKASI MQTT KE BACKEND) ==========
// Fungsi mengirim pesan error ke topik MQTT result
void publishError(const String& checkId, const String& action, const String& errorCode) {
  String payload = "{";
  payload += "\"status\":\"error\",";
  payload += "\"action\":\"" + jsonEscape(action) + "\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"error\":\"" + jsonEscape(errorCode) + "\",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  bool sent = false;
  for (int i = 0; i < 3 && !sent; i++) {
    if (!mqtt.connected()) connectMqtt();
    sent = mqtt.publish(resultTopic.c_str(), payload.c_str());
    if (!sent) { delay(120); mqtt.loop(); }
  }
  Serial.print("[MQTT] Publish Error    check_id="); Serial.print(checkId);
  Serial.print(" | error="); Serial.print(errorCode);
  Serial.print(" | sent="); Serial.println(sent ? "OK" : "FAIL");
}

// Fungsi mengirim hasil detak jantung (BPM) ke topik MQTT result
void publishHeartRate(const String& checkId, float bpm) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"heart_rate\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"heart_rate\":" + String(bpm, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  bool sent = false;
  for (int i = 0; i < 3 && !sent; i++) {
    if (!mqtt.connected()) connectMqtt();
    sent = mqtt.publish(resultTopic.c_str(), payload.c_str());
    if (!sent) { delay(120); mqtt.loop(); }
  }
  Serial.println();
  Serial.print("[MQTT] Publish HeartRate | BPM="); Serial.print(bpm, 2);
  Serial.print(" | sent="); Serial.print(sent ? "OK" : "FAIL"); Serial.println(".");
  if (sent) beepBuzzer(1000);  // Bunyikan buzzer 1 detik jika publish berhasil
}

// Fungsi mengirim hasil suhu tubuh (°C) ke topik MQTT result
void publishBodyTemperature(const String& checkId, float temp) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"body_temperature\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"body_temp\":" + String(temp, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  bool sent = false;
  for (int i = 0; i < 3 && !sent; i++) {
    if (!mqtt.connected()) connectMqtt();
    sent = mqtt.publish(resultTopic.c_str(), payload.c_str());
    if (!sent) { delay(120); mqtt.loop(); }
  }
  Serial.print("[MQTT] Publish BodyTemp   check_id="); Serial.print(checkId);
  Serial.print(" | Temp="); Serial.print(temp, 2); Serial.print(" C");
  Serial.print(" | sent="); Serial.println(sent ? "OK" : "FAIL");
  if (sent) beepBuzzer(1000);  // Bunyikan buzzer 1 detik jika publish berhasil
}

// ========== COMMAND HANDLER (PENANGAN PERINTAH MASUK DARI BACKEND) ==========
// Fungsi memproses perintah JSON yang masuk dari topik MQTT command
void handleCommandPayload(const String& payload) {
  String action  = extractJsonValue(payload, "action");
  String checkId = extractJsonValue(payload, "check_id");
  action.trim(); checkId.trim();
  if (checkId.length() == 0) checkId = "0";

  printSeparator();
  Serial.print("[MQTT] Command Diterima action="); Serial.print(action);
  Serial.print(" | check_id="); Serial.println(checkId);

  String errorCode = "";
  // Perintah ukur detak jantung
  if (action == "heart_rate") {
    float bpm = measureHeartRateBpm(errorCode, checkId);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishHeartRate(checkId, bpm);
    return;
  }
  // Perintah ukur suhu tubuh
  if (action == "body_temperature") {
    float tempVal = measureBodyTemperatureC(errorCode, checkId);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishBodyTemperature(checkId, tempVal);
    return;
  }
  publishError(checkId, action, "unknown_action");
}

// ========== SERVO (PENGONTROL BUKA KOTAK) ==========
// Fungsi memutar servo ke 45 derajat (posisi BUKA) selama 6 detik
void openServoForDuration(unsigned long durationMs) {
  (void)durationMs; // Nilai dari pemanggil diabaikan, selalu dikunci ke 6000 ms (6 detik)
  servoAutoCloseMs = 6000;
  snackServo.write(SERVO_OPEN_ANGLE); // Putar servo ke 45 derajat
  servoIsOpen      = true;
  servoOpenedAtMs  = millis();
  Serial.print("[SERVO] Buka kotak selama "); Serial.print(servoAutoCloseMs);
  Serial.println("-");
}

// Fungsi menguji gerakan servo saat booting dinyalakan (Tutup -> Buka -> Tutup)
void runServoBootTest() {
  if (!ENABLE_SERVO_BOOT_TEST) return;
  Serial.println("[SERVO] Boot test: tutup -> buka -> tutup");
  snackServo.write(SERVO_CLOSED_ANGLE); delay(500);
  snackServo.write(SERVO_OPEN_ANGLE);   delay(900);
  snackServo.write(SERVO_CLOSED_ANGLE); delay(500);
  Serial.println("[SERVO] Boot test selesai.");
}

// Fungsi mengecek apakah servo sudah terbuka melebihi 6 detik, jika ya putar kembali ke 0 derajat (TUTUP)
void closeServoIfNeeded() {
  if (!servoIsOpen) return;
  if (millis() - servoOpenedAtMs < servoAutoCloseMs) return;
  snackServo.write(SERVO_CLOSED_ANGLE); // Putar servo ke 0 derajat (TUTUP)
  servoIsOpen = false;
  Serial.println("[SERVO] Kotak tertutup otomatis.");
}

// ========== SERIAL DEBUG (PERINTAH KETIKAN SERIAL MONITOR) ==========
// Fungsi membaca ketikan perintah manual dari Serial Monitor untuk testing
void handleSerialDebugCommand() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim(); cmd.toLowerCase();
  if (cmd.length() == 0) return;

  if (cmd == "servo_test")  { runServoBootTest(); return; }
  if (cmd == "servo_open")  {
    snackServo.write(SERVO_OPEN_ANGLE);
    servoIsOpen = true; servoOpenedAtMs = millis(); servoAutoCloseMs = 60000;
    Serial.println("[DEBUG] Servo dibuka manual (60 detik).");
    return;
  }
  if (cmd == "servo_close") {
    snackServo.write(SERVO_CLOSED_ANGLE); servoIsOpen = false;
    Serial.println("[DEBUG] Servo ditutup manual.");
    return;
  }
  if (cmd == "button") {
    int state = digitalRead(BUTTON_PIN);
    Serial.print("[DEBUG] Button state="); Serial.print(state);
    Serial.print(" | Active state="); Serial.println(BUTTON_ACTIVE_STATE);
    return;
  }
  if (cmd == "mqtt_status") {
    Serial.print("[DEBUG] MQTT connected="); Serial.println(mqtt.connected() ? "YES" : "NO");
    Serial.print("[DEBUG] WiFi status="); Serial.println(WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
    return;
  }
  if (cmd == "scan_i2c") {
    scanI2cBus();
    return;
  }
  if (cmd == "mlx_reset") {
    mlxReady = false;
    Serial.println("[DEBUG] mlxReady di-reset, akan di-reinit saat pengukuran berikutnya.");
    return;
  }
  Serial.print("[DEBUG] Perintah tidak dikenal: "); Serial.println(cmd);
}

// ========== BOX BUTTON (PENANGAN TOMBOL FISIK KOTAK) ==========
// Fungsi mengirim event MQTT saat tombol fisik ditekan oleh pengguna
void publishButtonEvent(bool isRetry = false) {
  String payload = "{";
  payload += "\"event\":\"button_pressed\",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\",";
  payload += "\"sent_at_ms\":" + String(millis());
  payload += "}";
  bool sent = false;
  for (int i = 0; i < 3 && !sent; i++) {
    if (!mqtt.connected()) connectMqtt();
    sent = mqtt.publish(boxEventTopic.c_str(), payload.c_str());
    if (!sent) { delay(100); mqtt.loop(); }
  }
  if (sent) {
    waitingBoxDecision          = true;
    buttonDecisionRequestedAt   = millis();
    if (!isRetry) boxDecisionRetryCount = 0;
  }
  Serial.print("[BOX] Tombol ditekan - event sent="); Serial.print(sent ? "OK" : "FAIL");
  if (isRetry) { Serial.print(" (retry ke-"); Serial.print(boxDecisionRetryCount); Serial.print(")"); }
  Serial.println();
}

// Fungsi memproses data keputusan balasan dari backend Laravel (DIIZINKAN / DITOLAK)
void handleBoxDecisionPayload(const String& payload) {
  String allowOpen    = extractJsonValue(payload, "allow_open");
  String reason       = extractJsonValue(payload, "reason");
  String durationText = extractJsonValue(payload, "open_duration_ms");
  allowOpen.trim(); reason.trim(); durationText.trim();
  waitingBoxDecision   = false;
  boxDecisionRetryCount = 0;

  const unsigned long FIXED_OPEN_DURATION_MS = 6000;

  printSeparator();
  Serial.println("[BOX] === Keputusan Buka Kotak ===");
  Serial.print("[BOX] Allow Open        : "); Serial.println(allowOpen);
  Serial.print("[BOX] Reason            : "); Serial.println(reason);

  // Jika diizinkan oleh backend, buka pintu servo
  if ((allowOpen == "true" || allowOpen == "1") && reason == "allowed") {
    Serial.println("[BOX] Status            : DIIZINKAN - Kotak dibuka.");
    openServoForDuration(FIXED_OPEN_DURATION_MS);
  } else {
    Serial.println("[BOX] Status            : DITOLAK - Kotak tetap tertutup.");
  }
  printSeparator();
}

// ========== MQTT CALLBACK (CALLBACK PESAN MASUK MQTT) ==========
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) message += (char)payload[i];
  String incomingTopic = String(topic);
  Serial.print("[MQTT] Pesan masuk dari : "); Serial.println(incomingTopic);
  if (incomingTopic == commandTopic)     { handleCommandPayload(message); return; }
  if (incomingTopic == boxDecisionTopic) { handleBoxDecisionPayload(message); }
}

// ========== WIFI (KONEKSI WAKTU SENSORIAL) ==========
// Fungsi menghubungkan ESP32 ke jaringan Wi-Fi
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - startMs) < 20000) {
    delay(500);
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WiFi] Connection Failed");
    return;
  }
  logNetworkDiag();
}

// ========== MQTT CONNECT (KONEKSI KE BROKER MQTT) ==========
// Fungsi menghubungkan ESP32 ke Broker MQTT
void connectMqtt() {
  if (mqtt.connected()) return;
  String clientId = String("esp32_") + DEVICE_ID + "_" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.println("[MQTT] Connecting...");
  bool ok = strlen(MQTT_USER) > 0
            ? mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)
            : mqtt.connect(clientId.c_str());
  if (ok) {
    Serial.println("[MQTT] Connected");
    mqtt.subscribe(commandTopic.c_str());    // Subscribe topik perintah
    mqtt.subscribe(boxDecisionTopic.c_str()); // Subscribe topik keputusan kotak
  } else {
    Serial.print("[MQTT] Failed rc="); Serial.println(mqtt.state());
    if (millis() - lastNetworkDiagMs > 8000) { lastNetworkDiagMs = millis(); logNetworkDiag(); }
  }
}

// ========== SETUP (INISIALISASI PERANGKAT SAAT PERTAMA NYALA) ==========
void setup() {
  Serial.begin(115200);
  delay(1200);

  // Inisialisasi bus I2C dengan clock 50kHz agar MLX90614 stabil saat booting
  Wire.begin(21, 22);
  Wire.setClock(50000);
  delay(500);
  scanI2cBus();

  // Inisialisasi MAX30102 dengan clock 100kHz
  Wire.setClock(100000);
  bool maxOk = false;
  for (int attempt = 1; attempt <= 3; attempt++) {
    Serial.print("[SENSOR] Coba init MAX30102 ke-"); Serial.println(attempt);
    if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
      maxOk = true;
      break;
    }
    delay(500);
  }
  if (!maxOk) {
    Serial.println("[ERROR] MAX30102 tidak ditemukan! Periksa koneksi I2C.");
    while (1) delay(1000);
  }
  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x1F);
  particleSensor.setPulseAmplitudeIR(0x24);
  Serial.println("[SENSOR] MAX30102 OK");

  // Inisialisasi MLX90614
  Wire.setClock(50000);
  delay(300);
  Serial.println("[SENSOR] Mencoba init MLX90614...");
  for (int attempt = 1; attempt <= 5; attempt++) {
    Serial.print("[SENSOR] MLX90614 init attempt ke-"); Serial.println(attempt);
    if (mlx.begin()) {
      mlxReady = true;
      Serial.println("[SENSOR] MLX90614 OK");
      break;
    }
    delay(500);
  }
  if (!mlxReady) {
    Serial.println("[WARN] MLX90614 tidak ditemukan saat boot.");
    Serial.println("[WARN] Fitur suhu dinonaktifkan sementara, akan retry saat pengukuran.");
  }

  Wire.setClock(100000);

  // Buat topik MQTT spesifik berdasarkan DEVICE_ID
  commandTopic     = String("smartsnack/health/command/") + DEVICE_ID;
  resultTopic      = String("smartsnack/health/result/")  + DEVICE_ID;
  rawTopic         = String("smartsnack/health/raw/")     + DEVICE_ID;  // Topik data mentah real-time (grafik Flutter)
  boxEventTopic    = String("smartsnack/box/event/")       + DEVICE_ID;
  boxDecisionTopic = String("smartsnack/box/decision/")    + DEVICE_ID;

  // Konfigurasi pin tombol, servo, dan buzzer
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  snackServo.setPeriodHertz(50);
  snackServo.attach(SERVO_PIN, 500, 2400);
  snackServo.write(SERVO_CLOSED_ANGLE);
  Serial.println("[SERVO] Servo terpasang di pin 18 | Posisi awal: TUTUP");
  runServoBootTest();

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  Serial.println("[BUZZER] Active buzzer terpasang di pin 4 | Posisi awal: MATI");

  // Hubungkan ke Wi-Fi & MQTT Server
  connectWifi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(1024);
  mqtt.setKeepAlive(120);
  mqtt.setSocketTimeout(15);
  connectMqtt();

  printSeparator();
  Serial.println("System Ready");
}

// ========== LOOP (PERULANGAN UTAMA BERJALAN DENGAN KONTINU) ==========
void loop() {
  // Reconnect Wi-Fi otomatis jika terputus
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastWifiRetryMs > 5000) {
      lastWifiRetryMs = millis();
      Serial.println("[WiFi] Koneksi terputus, mencoba reconnect...");
      connectWifi();
    }
    delay(20);
    return;
  }

  // Reconnect MQTT otomatis jika terputus & jalankan mqtt.loop()
  if (!mqtt.connected()) {
    if (millis() - lastMqttReconnectMs > 3000) {
      lastMqttReconnectMs = millis();
      connectMqtt();
    }
  } else {
    mqtt.loop();
    if (millis() - lastMqttLoopKickMs > 5000) {
      lastMqttLoopKickMs = millis();
      Serial.println("[MQTT] Status : ACTIVE");
      printSeparator();
    }
  }

  // Cek penekanan tombol fisik dengan mekanisme Debounce & Cooldown
  bool reading = digitalRead(BUTTON_PIN);
  if (reading != lastButtonReading) { lastButtonEdgeMs = millis(); lastButtonReading = reading; }
  if ((millis() - lastButtonEdgeMs) > BUTTON_DEBOUNCE_MS) {
    if (reading == BUTTON_ACTIVE_STATE && !buttonPressLatched &&
        !waitingBoxDecision && !servoIsOpen &&
        (millis() - lastButtonPublishMs) > BUTTON_COOLDOWN_MS) {
      buttonPressLatched  = true;
      lastButtonPublishMs = millis();
      publishButtonEvent();
    }
    if (reading != BUTTON_ACTIVE_STATE) buttonPressLatched = false;
  }

  // Cek timeout balasan keputusan dari backend jika belum membalas
  if (waitingBoxDecision && (millis() - buttonDecisionRequestedAt) > BOX_DECISION_TIMEOUT_MS) {
    if (boxDecisionRetryCount < BOX_DECISION_MAX_RETRY) {
      boxDecisionRetryCount++;
      Serial.print("[BOX] Timeout menunggu keputusan, kirim ulang (");
      Serial.print(boxDecisionRetryCount); Serial.println(")");
      publishButtonEvent(true);
    } else {
      waitingBoxDecision    = false;
      boxDecisionRetryCount = 0;
      Serial.println("[BOX] Timeout - tidak ada keputusan dari backend.");
    }
  }

  // Panggil fungsi penutup otomatis servo
  closeServoIfNeeded();
  
  // Baca perintah debug serial manual dari keyboard
  handleSerialDebugCommand();
}
