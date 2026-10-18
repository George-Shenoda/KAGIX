#ifndef DOORCONTROL_H
#define DOORCONTROL_H

#include <Arduino.h>
#include <Servo.h>
#include <Keypad.h>

class DoorControl {
  private:
    Servo myservo;
    int servoPin;
    String password;
    String typed;
    bool isDoorOpen;
    unsigned long doorOpenTimer;
    const unsigned long DOOR_OPEN_DURATION;
    Keypad* customkeypad;
    char lastAnalogKey;
    unsigned long lastKeyDebounce;

    char scanAnalogColumnKeypad();

  public:
    DoorControl(int sPin, String pwd);
    void begin();
    void openDoor();
    void closeDoor();
    void update();
    bool getIsOpen();
    bool verifyPassword(String inputPwd);
    int getRemainingSeconds();
};

#endif
