#include "DoorControl.h"

// ============================================================================
// ARDUINO NANO 4x4 KEYPAD PIN ALLOCATION (5 PINS: D13, D12, D11, D10 + A1)
// - Rows R1..R4 connect to Digital Pins D13, D12, D11, D10.
// - Columns C1..C4 connect to Analog/Digital Pin A1 via a 4-resistor ladder
//   (C1: 0 ohm, C2: 1k, C3: 2.2k, C4: 4.7k with 1k pull-up to +5V).
//   This frees D5 (Buzzer), D7 (Matrix LED #2), D8 (Security Switch #2),
//   A2 (Window IR2), and A3 (Door PIR) on a single Arduino Nano!
// ============================================================================
const byte ROWS = 4;
const byte COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};
byte rowPins[ROWS] = {13, 12, 11, 10};
const int KEYPAD_COL_PIN = A1;

DoorControl::DoorControl(int sPin, String pwd) : DOOR_OPEN_DURATION(20000) {
  servoPin = sPin;
  password = pwd;
  typed = "";
  isDoorOpen = false;
  doorOpenTimer = 0;
  lastAnalogKey = 0;
  lastKeyDebounce = 0;
  customkeypad = nullptr;
}

void DoorControl::begin() {
  myservo.attach(servoPin);
  myservo.write(0);
  for (byte r = 0; r < ROWS; r++) {
    pinMode(rowPins[r], INPUT_PULLUP);
  }
  pinMode(KEYPAD_COL_PIN, INPUT_PULLUP);
}

char DoorControl::scanAnalogColumnKeypad() {
  char detected = 0;
  for (byte r = 0; r < ROWS; r++) {
    pinMode(rowPins[r], OUTPUT);
    digitalWrite(rowPins[r], LOW);
    delayMicroseconds(50);
    int adc = analogRead(KEYPAD_COL_PIN);
    pinMode(rowPins[r], INPUT_PULLUP);

    if (adc < 880) {
      byte col = 0;
      if (adc < 180) col = 0;       // C1 (0 ohm)
      else if (adc < 560) col = 1;  // C2 (1k ohm)
      else if (adc < 740) col = 2;  // C3 (2.2k ohm)
      else col = 3;                 // C4 (4.7k ohm)
      detected = keys[r][col];
      break;
    }
  }

  if (detected != lastAnalogKey) {
    if (millis() - lastKeyDebounce > 45) {
      lastKeyDebounce = millis();
      lastAnalogKey = detected;
      return detected;
    }
  }
  return 0;
}

void DoorControl::openDoor() {
  if (!isDoorOpen) {
    isDoorOpen = true;
    myservo.write(90);
    doorOpenTimer = millis();
  } else {
    doorOpenTimer = millis();
  }
}

void DoorControl::closeDoor() {
  if (isDoorOpen) {
    isDoorOpen = false;
    myservo.write(0);
  }
}

bool DoorControl::verifyPassword(String inputPwd) {
  return inputPwd == password;
}

int DoorControl::getRemainingSeconds() {
  if (!isDoorOpen) return 0;
  unsigned long elapsed = millis() - doorOpenTimer;
  if (elapsed >= DOOR_OPEN_DURATION) return 0;
  return (int)((DOOR_OPEN_DURATION - elapsed + 999) / 1000);
}

void DoorControl::update() {
  // 1. Auto close timer (20 seconds)
  if (isDoorOpen && (millis() - doorOpenTimer >= DOOR_OPEN_DURATION)) {
    closeDoor();
  }

  // 2. Read Keypad ('A' or '#' confirms password, 'C' or '*' clears)
  char key = scanAnalogColumnKeypad();
  if (key) {
    if (key == 'A' || key == '#') {
      if (typed == password) {
        openDoor();
      }
      typed = "";
    }
    else if (key == 'C' || key == '*') {
      typed = "";
    }
    else {
      typed += key;
    }
  }
}

bool DoorControl::getIsOpen() {
  return isDoorOpen;
}
