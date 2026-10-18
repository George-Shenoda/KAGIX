#include "Light.h"
#include <Adafruit_NeoPixel.h>

// Uses ONLY Matrix LED #1 (matrixIndoor on Pin D6)
extern Adafruit_NeoPixel matrixIndoor;

Light::Light(int switchPin, int LDRPin, int potPin) : OVERRIDE_DURATION(10000) {
  lightSwitch = switchPin; // Dedicated Switch #1 on Pin D3
  LDR = LDRPin;            // Dedicated LDR on Pin A0
  lightPOT = potPin;       // Dedicated Potentiometer #1 on Pin A6

  isIndoorLightOn = false;
  lastSwitchState = HIGH;
  isAutoMode = true;
  manualOverrideTimer = 0;

  lastPotValue = -1;
  isThresholdOverridden = false;
  ldrThreshold = 512;
  lastLdrValue = 500;

  matrixBrightness = MATRIX_BRIGHTNESS;
}

void Light::begin() {
  lastSwitchState = digitalRead(lightSwitch);
}

void Light::setBrightness(int newBrightness) {
  matrixBrightness = constrain(newBrightness, 0, 255);
  matrixIndoor.setBrightness(matrixBrightness);
  if (isIndoorLightOn) {
    refreshMatrix();
  }
}

int Light::getBrightness() {
  return matrixBrightness;
}

void Light::setBluetoothThreshold(int newThr) {
  ldrThreshold = constrain(newThr, 0, 1023);
  isThresholdOverridden = true;
}

int Light::getThreshold() {
  return ldrThreshold;
}

int Light::getLastLDRValue() {
  return lastLdrValue;
}

void Light::returnToPotentiometer() {
  isThresholdOverridden = false;
}

void Light::refreshMatrix() {
  uint32_t c = isIndoorLightOn ? matrixIndoor.Color(255, 255, 255) : matrixIndoor.Color(0, 0, 0);
  for (uint16_t i = 0; i < MATRIX_LED_COUNT; i++) {
    matrixIndoor.setPixelColor(i, c);
  }
  matrixIndoor.show();
}

void Light::lightOn() {
  if (isIndoorLightOn) return;
  isIndoorLightOn = true;
  refreshMatrix();
}

void Light::lightOff() {
  if (!isIndoorLightOn) return;
  isIndoorLightOn = false;
  refreshMatrix();
}

bool Light::getIndoorLight() {
  return isIndoorLightOn;
}

bool Light::getIsAutoMode() {
  return isAutoMode;
}

void Light::enableAutoMode() {
  isAutoMode = true;
}

void Light::disableAutoMode() {
  isAutoMode = false;
  manualOverrideTimer = millis();
}

void Light::toggleLightBtn() {
  int currentSwitchState = digitalRead(lightSwitch);

  if (currentSwitchState != lastSwitchState) {
    lastSwitchState = currentSwitchState;
    disableAutoMode();

    if (currentSwitchState == HIGH) {
      lightOn();
    } else {
      lightOff();
    }
  }
}

void Light::LDRCheck() {
  // Read Dedicated Potentiometer #1 on Pin A6
  int currentPotValue = analogRead(lightPOT);

  if (lastPotValue == -1 || abs(currentPotValue - lastPotValue) > 10) {
    isThresholdOverridden = false;
    lastPotValue = currentPotValue;
  }

  if (isThresholdOverridden == false) {
    ldrThreshold = currentPotValue;
  }

  if (isAutoMode == false) {
    if (millis() - manualOverrideTimer >= OVERRIDE_DURATION) {
      enableAutoMode();
    }
  }

  lastLdrValue = analogRead(LDR);

  if (isAutoMode == true) {
    if (lastLdrValue < ldrThreshold) {
      lightOn();
    } else {
      lightOff();
    }
  }
}
