#include <Wire.h>
#include "MAX30105.h"

MAX30105 sensor;

void setup() {
  Serial.begin(115200);

  Wire.begin(21, 22);

  if (!sensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("Sensor tidak terdeteksi!");
    while (1);
  }

  Serial.println("Sensor OK");

  // Konfigurasi sensor
  sensor.setup(
    0x7F,   // LED brightness (0-255)
    4,      // Sample Average
    2,      // LED Mode (Red + IR)
    100,    // Sample Rate
    411,    // Pulse Width
    4096    // ADC Range
  );

  Serial.println("LED aktif...");
}

void loop() {
  // Membaca data terus agar LED tetap bekerja
  Serial.print("IR : ");
  Serial.print(sensor.getIR());

  Serial.print("  RED : ");
  Serial.println(sensor.getRed());

  delay(100);
}