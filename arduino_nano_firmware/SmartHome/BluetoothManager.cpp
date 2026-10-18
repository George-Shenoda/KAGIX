#include "BluetoothManager.h"
#include "Light.h"
#include "ClimateControl.h"
#include "DoorControl.h"
#include "SecuritySystem.h"

extern Light light;
extern ClimateControl climate;
extern DoorControl door;
extern SecuritySystem security;

extern bool isSecurityArmed;
extern bool isWindowOpen;
extern bool isMotionDetected;
extern float currentTemp;
extern float currentHum;
extern float tempThreshold;
extern bool isFanOn;

void BluetoothManager::begin(long baudRate) {
  Serial.begin(baudRate);
}

void BluetoothManager::readCommand() {
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() == 0) return;

    // -- 1. DOOR & 2. SECURITY --
    if (cmd == "DOOR:OPEN") door.openDoor();
    else if (cmd == "DOOR:CLOSE" || cmd == "DOOR:AUTO_CLOSED") door.closeDoor();
    else if (cmd.startsWith("PIN:")) {
      String pin = cmd.substring(4);
      if (door.verifyPassword(pin)) {
        door.openDoor();
      }
    }
    else if (cmd == "SEC:1") isSecurityArmed = true;
    else if (cmd == "SEC:0") {
      isSecurityArmed = false;
      security.clearAlarm();
    }
    else if (cmd == "ALARM:CLEAR") {
      security.clearAlarm();
    }

    // -- 3. INDOOR LIGHTING (Matrix #1 on D6, Switch #1 on D3, LDR on A0, Pot #1 on A6) --
    else if (cmd == "LIGHT:1") { light.disableAutoMode(); light.lightOn(); }
    else if (cmd == "LIGHT:0") { light.disableAutoMode(); light.lightOff(); }
    else if (cmd == "LIGHT:AUTO" || cmd == "LAUTO:1") light.enableAutoMode();
    else if (cmd == "LAUTO:0") light.disableAutoMode();
    else if (cmd.startsWith("L_THR:")) light.setBluetoothThreshold(cmd.substring(6).toInt());
    else if (cmd == "L_THR:AUTO") light.returnToPotentiometer();
    else if (cmd.startsWith("BRI:")) light.setBrightness(cmd.substring(4).toInt());

    // -- 4. CLIMATE / FAN (DHT11 on D4, Fan on D9, Pot #2 on A7) --
    else if (cmd == "FAN:1") climate.setManualFan(true);
    else if (cmd == "FAN:0") climate.setManualFan(false);
    else if (cmd == "FAN:AUTO" || cmd == "FAUTO:1") climate.setAutoFan();
    else if (cmd == "FAUTO:0") climate.setManualFan(isFanOn);
    else if (cmd.startsWith("THR:")) climate.setBluetoothThreshold(cmd.substring(4).toFloat());
    else if (cmd == "THR:AUTO") climate.returnToPotentiometer();
  }
}

void BluetoothManager::sendStatus() {
  Serial.print("TEMP:");  Serial.print(currentTemp, 1);
  Serial.print(",HUM:");  Serial.print(currentHum, 0);
  Serial.print(",THR:");  Serial.print(tempThreshold, 1);
  Serial.print(",DOOR:"); Serial.print(door.getIsOpen() ? 1 : 0);
  Serial.print(",SEC:");  Serial.print(isSecurityArmed ? 1 : 0);
  Serial.print(",WIN:");  Serial.print(isWindowOpen ? 1 : 0);
  Serial.print(",MOT:");  Serial.print(isMotionDetected ? 1 : 0);
  Serial.print(",LIN:");  Serial.print(light.getIndoorLight() ? 1 : 0);
  Serial.print(",FAN:");  Serial.print(isFanOn ? 1 : 0);
  Serial.print(",EXT:");  Serial.print(security.getIsExteriorLightOn() ? 1 : 0);
  Serial.print(",LAUTO:"); Serial.print(light.getIsAutoMode() ? 1 : 0);
  Serial.print(",FAUTO:"); Serial.print(climate.getIsAutoMode() ? 1 : 0);
  Serial.print(",LTHR:"); Serial.print(light.getThreshold());
  Serial.print(",BRI:");  Serial.print(light.getBrightness());
  Serial.print(",LUX:");  Serial.print(light.getLastLDRValue());
  Serial.print(",REM:");  Serial.println(door.getRemainingSeconds());
}
