#include "ClimateControl.h"
#include <dht.h>

extern dht DHT;
extern float currentTemp;
extern float currentHum;
extern float tempThreshold;
extern bool isFanOn;

ClimateControl::ClimateControl(int dPin, int mPin, int pPin) {
  dhtPin = dPin;
  motorPin = mPin;
  potPin = pPin; // Dedicated Potentiometer #2 on Arduino Nano Pin A7
  lastDHTReadTime = 0;
  isAutoMode = true;
  lastPotValue = -1;
  isThresholdOverridden = false;
}

void ClimateControl::begin() {
  pinMode(motorPin, OUTPUT);
}

void ClimateControl::setBluetoothThreshold(float newThr) {
  tempThreshold = newThr;
  isThresholdOverridden = true;
}

void ClimateControl::setManualFan(bool turnOn) {
  isAutoMode = false;
  if (turnOn) {
    digitalWrite(motorPin, HIGH);
    isFanOn = true;
  } else {
    digitalWrite(motorPin, LOW);
    isFanOn = false;
  }
}

void ClimateControl::setAutoFan() {
  isAutoMode = true;
}

void ClimateControl::returnToPotentiometer() {
  isThresholdOverridden = false;
}

bool ClimateControl::getIsAutoMode() {
  return isAutoMode;
}

void ClimateControl::update() {
  // 1. Read DHT11 every 2000ms
  if (millis() - lastDHTReadTime >= 2000) {
    lastDHTReadTime = millis();
    int chk = DHT.read11(dhtPin);
    if (chk == DHTLIB_OK) {
      currentTemp = DHT.temperature;
      currentHum = DHT.humidity;
    }
  }

  // 2. "Smart Knob" Logic for Temperature Threshold (Potentiometer #2 on A7)
  int currentPotValue = analogRead(potPin);

  if (lastPotValue == -1 || abs(currentPotValue - lastPotValue) > 10) {
    isThresholdOverridden = false;
    lastPotValue = currentPotValue;
  }

  if (isThresholdOverridden == false) {
    tempThreshold = map(currentPotValue, 0, 1023, 0, 55);
  }

  // 3. Control Fan (Only if in Auto Mode)
  if (isAutoMode == true) {
    if (currentTemp > tempThreshold) {
      digitalWrite(motorPin, HIGH);
      isFanOn = true;
    } else {
      digitalWrite(motorPin, LOW);
      isFanOn = false;
    }
  }
}
