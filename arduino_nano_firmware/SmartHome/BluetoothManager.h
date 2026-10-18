#ifndef BLUETOOTHMANAGER_H
#define BLUETOOTHMANAGER_H

#include <Arduino.h>

class BluetoothManager {
  public:
    void begin(long baudRate);
    void readCommand();
    void sendStatus();
};

#endif
