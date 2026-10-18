#ifndef SECURITYSYSTEM_H
#define SECURITYSYSTEM_H

#include <Arduino.h>

// Dedicated Matrix LED #2 on Pin D7 for Function 2 (Security Exterior Motion Light)
#define SEC_MATRIX_PIN 7
#define SEC_MATRIX_LED_COUNT 64
#define SEC_MATRIX_BRIGHTNESS 80

class SecuritySystem {
  private:
    int switchPin;
    int irPin;
    int pirPin;
    int buzzerPin;

    int lastSwitchState;

    // Non-blocking timers for dedicated Exterior Matrix LED #2 & Buzzer
    bool isMotionLightOn;
    unsigned long motionLightTimer;
    const unsigned long MOTION_LIGHT_DURATION = 60000; // 60 seconds

    bool isBuzzerOn;
    unsigned long buzzerTimer;
    const unsigned long BUZZER_INTERVAL = 200; // 200ms blink

  public:
    SecuritySystem(int swPin, int ir2Pin, int pPin, int bzPin);
    void begin();
    void clearAlarm();
    bool getIsExteriorLightOn();
    void update();
};

#endif
