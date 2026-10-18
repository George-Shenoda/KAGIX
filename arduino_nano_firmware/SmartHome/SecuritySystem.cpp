#include "SecuritySystem.h"
#include <Adafruit_NeoPixel.h>

// Uses ONLY Matrix LED #2 (matrixSecurity on Pin D7) — never touches matrixIndoor!
extern Adafruit_NeoPixel matrixSecurity;
extern bool isSecurityArmed;
extern bool isWindowOpen;
extern bool isMotionDetected;

SecuritySystem::SecuritySystem(int swPin, int ir2Pin, int pPin, int bzPin) {
  switchPin = swPin; // Dedicated Switch #2 on Pin D8
  irPin = ir2Pin;    // Dedicated Window IR2 Sensor on Pin A2 (D16)
  pirPin = pPin;     // Dedicated Door PIR Motion Sensor on Pin A3 (D17)
  buzzerPin = bzPin; // Dedicated Alarm Buzzer on Pin D5

  lastSwitchState = HIGH;
  isMotionLightOn = false;
  motionLightTimer = 0;
  isBuzzerOn = false;
  buzzerTimer = 0;
}

void SecuritySystem::begin() {
  pinMode(switchPin, INPUT_PULLUP);
  pinMode(irPin, INPUT_PULLUP); // Active LOW window intruder sensor
  pinMode(pirPin, INPUT);
  pinMode(buzzerPin, OUTPUT);
  lastSwitchState = digitalRead(switchPin);
}

void SecuritySystem::clearAlarm() {
  digitalWrite(buzzerPin, LOW);
  isBuzzerOn = false;
}

bool SecuritySystem::getIsExteriorLightOn() {
  return isMotionLightOn;
}

void SecuritySystem::update() {
  // 1. Toggle "Armed" state when physical Switch #2 (D8) is flipped
  int currentSwitchState = digitalRead(switchPin);
  if (currentSwitchState != lastSwitchState) {
    lastSwitchState = currentSwitchState;
    isSecurityArmed = (currentSwitchState == LOW);
  }

  // 2. Read Dedicated Window IR2 Sensor (A2) and Door PIR Motion Sensor (A3)
  int irState = digitalRead(irPin);
  int motionState = digitalRead(pirPin);

  // FIXED: Update global isWindowOpen so BluetoothManager sends WIN:1 on breach
  isWindowOpen = (irState == LOW);
  isMotionDetected = (motionState == HIGH);

  // 3. Security Logic (Only acts if Armed via Switch #2 or Bluetooth)
  if (isSecurityArmed) {

    // --- PIR Motion Sensor (Turns ON Dedicated Exterior Matrix LED #2 on Pin D7 for 60s) ---
    if (motionState == HIGH) {
      if (!isMotionLightOn) {
        isMotionLightOn = true;
        for (uint16_t i = 0; i < SEC_MATRIX_LED_COUNT; i++) {
          matrixSecurity.setPixelColor(i, matrixSecurity.Color(255, 0, 0));
        }
        matrixSecurity.show();
      }
      motionLightTimer = millis();
    }

    // --- Window IR2 Intruder Sensor (Triggers Buzzer on Pin D5 without Serial spam) ---
    if (isWindowOpen) {
      if (millis() - buzzerTimer >= BUZZER_INTERVAL) {
        buzzerTimer = millis();
        isBuzzerOn = !isBuzzerOn;
        digitalWrite(buzzerPin, isBuzzerOn ? HIGH : LOW);
      }
    } else {
      digitalWrite(buzzerPin, LOW);
      isBuzzerOn = false;
    }
  } else {
    // Ensure buzzer and exterior security matrix light turn off when disarmed
    digitalWrite(buzzerPin, LOW);
    isBuzzerOn = false;
    if (isMotionLightOn) {
      isMotionLightOn = false;
      matrixSecurity.clear();
      matrixSecurity.show();
    }
  }

  // 4. Exterior Matrix LED #2 Auto-Turnoff (after 60 seconds of no motion)
  if (isMotionLightOn && (millis() - motionLightTimer >= MOTION_LIGHT_DURATION)) {
    isMotionLightOn = false;
    matrixSecurity.clear();
    matrixSecurity.show();
  }
}
