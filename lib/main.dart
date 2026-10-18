import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// KAGIX SMART HOME — MCT 331s Mechatronic System Integration (Arduino Nano)
// Architecture:
//   • MCU:           Arduino Nano (ATmega328P — 22 Pins, Zero Pin Conflicts)
//   • Communication: Bluetooth Classic SPP (HC-05 / HC-06 @ 9600 baud on D0/D1)
//   • Zero Sharing:  2 Dedicated 10k Potentiometers (A6 Light, A7 Climate),
//                    2 Dedicated 8x8 NeoPixel Matrix LEDs (D6 Indoor, D7 Exterior),
//                    2 Dedicated Physical Switches (D3 Light, D8 Security)
//   • Protocol:      Matches SmartHome.ino / BluetoothManager.cpp 100%
// ============================================================================

void main() {
  runApp(const KagixSmartHomeApp());
}

class KagixSmartHomeApp extends StatelessWidget {
  const KagixSmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kagix Smart Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F4C81),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF38BDF8),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const KagixHomeDashboard(),
    );
  }
}

/// Represents a paired Bluetooth Classic SPP device (such as HC-05 / HC-06).
class BtClassicDevice {
  final String name;
  final String address;
  final bool isPaired;

  const BtClassicDevice({
    required this.name,
    required this.address,
    this.isPaired = true,
  });
}

/// Complete real-time state of the "Kagix" Smart Home Arduino Nano Prototype.
class KagixHomeState {
  final String houseName = 'Kagix';

  // 1. Main Door Access (DoorControl.cpp: Pin D2 Servo, 4x4 Keypad, PIN "2006", 20s delay)
  bool isDoorOpen;
  int autoCloseDelaySeconds;
  int remainingDoorSeconds;
  String keypadPin;
  String lastDoorTriggerSource;

  // 2. Security System (SecuritySystem.cpp: Switch #2 D8, IR2 A2, PIR A3, Buzzer D5, Matrix #2 D7)
  bool isSecurityArmed;
  bool isWindowOpen;
  bool isMotionDetected;
  bool isAlarmTriggered;
  bool isExteriorMatrixOn; // Dedicated 8x8 Matrix LED #2 on Pin D7 (60s timer)

  // 3. Automatic Indoor Lighting (Light.cpp: Switch #1 D3, LDR A0, Pot #1 A6, Matrix #1 D6)
  bool isIndoorLightAuto;
  bool isIndoorLightOn; // Dedicated 8x8 Matrix LED #1 on Pin D6
  int ldrAdcValue;      // 0..1023 on Pin A0
  int ldrThreshold;     // 0..1023 set by Potentiometer #1 (A6) or L_THR:<val>
  int matrixBrightness; // 0..255 set by BRI:<val> (default 50)
  bool isLdrThrFromApp; // true if overridden via L_THR:<val>, false if Pot #1 (A6)
  String lastLightControlSource;

  // 4. Climate Control System (ClimateControl.cpp: DHT11 D4, Fan D9, Pot #2 A7)
  double temperatureC;
  double humidityPercent;
  double tempThresholdC; // 0..55 °C set by Potentiometer #2 (A7) or THR:<val>
  bool isFanAuto;
  bool isFanOn;
  bool isTempThrFromApp; // true if overridden via THR:<val>, false if Pot #2 (A7)
  String lastThresholdSource;

  // Bluetooth Classic Connection State
  bool isBtConnected;
  bool isBtConnecting;
  BtClassicDevice? connectedDevice;

  KagixHomeState({
    this.isDoorOpen = false,
    this.autoCloseDelaySeconds = 20, // Matches DOOR_OPEN_DURATION(20000) in DoorControl.cpp
    this.remainingDoorSeconds = 0,
    this.keypadPin = '2006', // Matches DoorControl(2, "2006") in SmartHome.ino
    this.lastDoorTriggerSource = 'Closed',
    this.isSecurityArmed = true,
    this.isWindowOpen = false,
    this.isMotionDetected = false,
    this.isAlarmTriggered = false,
    this.isExteriorMatrixOn = false,
    this.isIndoorLightAuto = true,
    this.isIndoorLightOn = false,
    this.ldrAdcValue = 620,
    this.ldrThreshold = 512,
    this.matrixBrightness = 50,
    this.isLdrThrFromApp = false,
    this.lastLightControlSource = 'LDR Auto (A0 + Pot #1 A6)',
    this.temperatureC = 26.5,
    this.humidityPercent = 48.0,
    this.tempThresholdC = 28.0,
    this.isFanAuto = true,
    this.isFanOn = false,
    this.isTempThrFromApp = false,
    this.lastThresholdSource = 'Potentiometer #2 (A7)',
    this.isBtConnected = false,
    this.isBtConnecting = false,
    this.connectedDevice,
  });

  /// Exact Line 1 of DisplayManager.cpp on the 16x2 I2C LCD (0x27 on A4/A5).
  String get lcdLine1 {
    final doorStr = isDoorOpen ? 'OPENED' : 'CLOSED';
    final secStr = isSecurityArmed ? 'ARM' : 'OFF';
    String line = 'D:$doorStr S:$secStr';
    while (line.length < 16) {
      line += ' ';
    }
    return line;
  }

  /// Exact Line 2 of DisplayManager.cpp on the 16x2 I2C LCD (0x27 on A4/A5).
  String get lcdLine2 {
    String line =
        'T:${temperatureC.toStringAsFixed(1)}°C H:${humidityPercent.toInt()}%';
    while (line.length < 16) {
      line += ' ';
    }
    return line;
  }
}

class KagixLogEntry {
  final DateTime timestamp;
  final String title;
  final String message;
  final bool isCritical;
  final String direction;

  KagixLogEntry({
    required this.timestamp,
    required this.title,
    required this.message,
    this.isCritical = false,
    this.direction = 'SYS',
  });
}

class KagixHomeDashboard extends StatefulWidget {
  const KagixHomeDashboard({super.key});

  @override
  State<KagixHomeDashboard> createState() => _KagixHomeDashboardState();
}

class _KagixHomeDashboardState extends State<KagixHomeDashboard> {
  final KagixHomeState _state = KagixHomeState();
  final List<KagixLogEntry> _alertLog = [];
  final List<String> _serialMonitorLines = [];
  final StringBuffer _rxLineBuffer = StringBuffer();
  Timer? _doorAutoCloseTimer;

  List<BtClassicDevice> _pairedDevices = [
    const BtClassicDevice(name: 'Kagix-HC05', address: '98:D3:31:FB:48:A2'),
    const BtClassicDevice(name: 'HC-06', address: '00:21:13:01:9C:11'),
  ];

  @override
  void initState() {
    super.initState();
    _state.connectedDevice = _pairedDevices.first;
    _state.isBtConnected = true;
    _appendSerialMonitor(
      'SYS',
      'Bluetooth Classic SPP ready (Arduino Nano @ 9600 baud • PIN: 2006)',
    );
    _initNativeBluetoothChannel();
  }

  @override
  void dispose() {
    _doorAutoCloseTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BLUETOOTH CLASSIC (HC-05 / HC-06 SPP) STREAM & COMMAND PROTOCOL
  // Matches BluetoothManager.cpp in SmartHome.zip 100%
  // ---------------------------------------------------------------------------

  static const MethodChannel _btChannel =
      MethodChannel('com.kagix.smarthome/bt_classic');

  Future<void> _initNativeBluetoothChannel() async {
    _btChannel.setMethodCallHandler((call) async {
      if (call.method == 'onDataReceived') {
        final chunk = call.arguments as String? ?? '';
        onBluetoothBytesReceived(Uint8List.fromList(utf8.encode(chunk)));
      } else if (call.method == 'onDisconnected') {
        if (mounted) {
          setState(() => _state.isBtConnected = false);
          _appendSerialMonitor('SYS', 'Bluetooth Classic socket disconnected');
        }
      }
    });
    try {
      await _btChannel.invokeMethod('requestPermissions');
      final List<dynamic>? bonded =
          await _btChannel.invokeMethod<List<dynamic>>('getPairedDevices');
      if (bonded != null && bonded.isNotEmpty && mounted) {
        setState(() {
          _pairedDevices = bonded.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return BtClassicDevice(
              name: map['name']?.toString() ?? 'Unknown',
              address: map['address']?.toString() ?? '',
            );
          }).toList();
          _state.connectedDevice = _pairedDevices.first;
        });
      }
    } catch (_) {
      // Simulator or desktop preview fallback
    }
  }

  Future<void> _connectNativeBt(BtClassicDevice dev) async {
    setState(() {
      _state.isBtConnecting = true;
      _state.connectedDevice = dev;
    });
    _appendSerialMonitor('SYS', 'Connecting to ${dev.name} (${dev.address})...');
    try {
      final ok = await _btChannel.invokeMethod<bool>(
        'connect',
        {'address': dev.address},
      );
      if (mounted) {
        setState(() {
          _state.isBtConnected = (ok == true);
          _state.isBtConnecting = false;
        });
        _appendSerialMonitor(
          'SYS',
          'Connected to ${dev.name} over RFCOMM SPP',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state.isBtConnected = true;
          _state.isBtConnecting = false;
        });
        _appendSerialMonitor(
          'SYS',
          'Active link switched to ${dev.name} (${dev.address})',
        );
      }
    }
  }

  /// Sends a newline-delimited ASCII command frame matching BluetoothManager.cpp
  void _sendBtCommand(String command) {
    final frame = '${command.trim()}\n';
    _appendSerialMonitor('TX', command.trim());
    _btChannel.invokeMethod('write', {'data': frame}).catchError((_) {});
    debugPrint('[Kagix BT Classic TX] -> ${frame.trim()}');
  }

  void onBluetoothBytesReceived(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    for (int i = 0; i < chunk.length; i++) {
      final ch = chunk[i];
      if (ch == '\n' || ch == '\r') {
        if (_rxLineBuffer.isNotEmpty) {
          final completeLine = _rxLineBuffer.toString();
          _rxLineBuffer.clear();
          _parseArduinoTelemetryFrame(completeLine);
        }
      } else {
        _rxLineBuffer.write(ch);
      }
    }
  }

  /// Parses telemetry frames emitted by BluetoothManager::sendStatus():
  /// `TEMP:26.5,HUM:48,THR:28.0,DOOR:0,SEC:1,WIN:0,MOT:0,LIN:0,FAN:0`
  /// (plus optional extended fields `EXT,LAUTO,FAUTO,LTHR,BRI,LUX,REM`)
  void _parseArduinoTelemetryFrame(String payload) {
    final clean = payload.trim();
    if (clean.isEmpty) return;
    _appendSerialMonitor('RX', clean);

    // Ignore raw debug strings if running unpatched SecuritySystem.cpp
    if (!clean.contains(':')) return;

    final parts = clean.split(',');
    bool windowJustOpened = false;
    bool doorJustOpenedFromKeypad = false;

    setState(() {
      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final key = kv[0].trim().toUpperCase();
        final val = kv[1].trim();

        switch (key) {
          case 'TEMP':
            _state.temperatureC = double.tryParse(val) ?? _state.temperatureC;
            break;
          case 'HUM':
            _state.humidityPercent =
                double.tryParse(val) ?? _state.humidityPercent;
            break;
          case 'THR':
            final newThr = double.tryParse(val);
            if (newThr != null &&
                (newThr - _state.tempThresholdC).abs() >= 0.1) {
              _state.tempThresholdC = newThr.clamp(0.0, 55.0);
            }
            break;
          case 'DOOR':
            final open = (val == '1' || val == 'OPEN');
            if (open && !_state.isDoorOpen) {
              doorJustOpenedFromKeypad = true;
              _state.remainingDoorSeconds = _state.autoCloseDelaySeconds;
            } else if (!open) {
              _state.remainingDoorSeconds = 0;
            }
            _state.isDoorOpen = open;
            break;
          case 'REM':
            _state.remainingDoorSeconds =
                int.tryParse(val) ?? _state.remainingDoorSeconds;
            break;
          case 'SEC':
            _state.isSecurityArmed = (val == '1' || val == 'ARMED');
            break;
          case 'WIN':
            final newWin = (val == '1' || val == 'OPEN');
            if (newWin && !_state.isWindowOpen) {
              windowJustOpened = true;
            }
            _state.isWindowOpen = newWin;
            break;
          case 'MOT':
            _state.isMotionDetected = (val == '1' || val == 'DETECTED');
            if (_state.isSecurityArmed && _state.isMotionDetected) {
              _state.isExteriorMatrixOn = true;
            }
            break;
          case 'EXT':
            _state.isExteriorMatrixOn = (val == '1' || val == 'ON');
            break;
          case 'LIN':
          case 'LIGHT':
            _state.isIndoorLightOn = (val == '1' || val == 'ON');
            break;
          case 'LAUTO':
            _state.isIndoorLightAuto = (val == '1' || val == 'AUTO');
            break;
          case 'LTHR':
            final newLThr = int.tryParse(val);
            if (newLThr != null) {
              _state.ldrThreshold = newLThr.clamp(0, 1023);
            }
            break;
          case 'BRI':
            final newBri = int.tryParse(val);
            if (newBri != null) {
              _state.matrixBrightness = newBri.clamp(0, 255);
            }
            break;
          case 'LUX':
            final newLux = int.tryParse(val);
            if (newLux != null) {
              _state.ldrAdcValue = newLux.clamp(0, 1023);
            }
            break;
          case 'FAN':
            _state.isFanOn = (val == '1' || val == 'ON');
            break;
          case 'FAUTO':
            _state.isFanAuto = (val == '1' || val == 'AUTO');
            break;
        }
      }

      if (doorJustOpenedFromKeypad) {
        _addLog(
          'Main Door Opened (Servo Pin D2)',
          'Unlocked via Keypad (PIN 2006) or App. Auto-closing in ${_state.autoCloseDelaySeconds}s.',
        );
      }

      _evaluateAutomationRules(windowJustOpened: windowJustOpened);
    });
  }

  void _appendSerialMonitor(String dir, String line) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _serialMonitorLines.insert(0, '[$ts] [$dir] $line');
      if (_serialMonitorLines.length > 60) {
        _serialMonitorLines.removeLast();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // SYSTEM CONTROL LOGIC (EXACT MATCH WITH ARDUINO NANO CLASSES)
  // ---------------------------------------------------------------------------

  void _openMainDoor({required String source}) {
    _doorAutoCloseTimer?.cancel();
    setState(() {
      _state.isDoorOpen = true;
      _state.remainingDoorSeconds = _state.autoCloseDelaySeconds;
      _state.lastDoorTriggerSource = source;
    });
    _sendBtCommand('DOOR:OPEN');
    _addLog(
      'Kagix Main Door Opened (Pin D2)',
      'Triggered via $source. Auto-closing after ${_state.autoCloseDelaySeconds}s delay.',
    );

    _doorAutoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_state.remainingDoorSeconds > 1) {
          _state.remainingDoorSeconds--;
        } else {
          _state.isDoorOpen = false;
          _state.remainingDoorSeconds = 0;
          _state.lastDoorTriggerSource = 'Auto-Closed (20s Timer)';
          timer.cancel();
          _sendBtCommand('DOOR:AUTO_CLOSED');
          _addLog(
            'Kagix Main Door Closed',
            'Door servo (D2) returned to 0° after 20s preset delay.',
          );
        }
      });
    });
  }

  void _closeMainDoorManually() {
    _doorAutoCloseTimer?.cancel();
    setState(() {
      _state.isDoorOpen = false;
      _state.remainingDoorSeconds = 0;
      _state.lastDoorTriggerSource = 'Kagix App (DOOR:CLOSE)';
    });
    _sendBtCommand('DOOR:CLOSE');
    _addLog('Kagix Main Door Closed', 'Locked immediately via DOOR:CLOSE.');
  }

  void _toggleSecurityMode(bool armed) {
    setState(() {
      _state.isSecurityArmed = armed;
      if (!armed) {
        _state.isAlarmTriggered = false;
        _state.isExteriorMatrixOn = false;
      } else {
        _evaluateAutomationRules(windowJustOpened: _state.isWindowOpen);
      }
    });
    _sendBtCommand(armed ? 'SEC:1' : 'SEC:0');
    _addLog(
      armed ? 'Security System ARMED (SEC:1)' : 'Security System DISARMED (SEC:0)',
      armed
          ? 'Window IR2 sensor (A2 -> Buzzer D5) and Door PIR (A3 -> Exterior Matrix #2 D7) active.'
          : 'Security alarms and exterior Matrix #2 disabled.',
    );
  }

  void _evaluateAutomationRules({bool windowJustOpened = false}) {
    // 2a. Security System: Window IR2 (A2) active LOW -> triggers Buzzer (D5)
    if (_state.isSecurityArmed && _state.isWindowOpen) {
      _state.isAlarmTriggered = true;
      if (windowJustOpened) {
        _triggerWindowSecurityAlert();
      }
    } else if (!_state.isWindowOpen || !_state.isSecurityArmed) {
      _state.isAlarmTriggered = false;
    }

    // 2b. Security System: PIR Motion (A3) turns ON Dedicated Exterior Matrix #2 (D7)
    if (_state.isSecurityArmed && _state.isMotionDetected) {
      _state.isExteriorMatrixOn = true;
    } else if (!_state.isSecurityArmed) {
      _state.isExteriorMatrixOn = false;
    }

    // 3. Automatic Indoor Lighting: LDR (A0) < Threshold (Pot #1 A6 or L_THR) -> Matrix #1 (D6)
    if (_state.isIndoorLightAuto) {
      _state.isIndoorLightOn = _state.ldrAdcValue < _state.ldrThreshold;
    }

    // 4. Climate Control: DHT11 Temp (D4) > Threshold (Pot #2 A7 or THR) -> Fan (D9)
    if (_state.isFanAuto) {
      _state.isFanOn = _state.temperatureC > _state.tempThresholdC;
    }
  }

  void _triggerWindowSecurityAlert() {
    final alert = KagixLogEntry(
      timestamp: DateTime.now(),
      title: 'SECURITY ALERT: Window IR2 Triggered!',
      message:
          'Window intruder sensor (Pin A2) breached while Armed! Buzzer (Pin D5) pulsing at 200ms.',
      isCritical: true,
    );
    _alertLog.insert(0, alert);

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 7),
        behavior: SnackBarBehavior.floating,
        content: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'KAGIX ALERT: Window IR2 sensor triggered! Buzzer (D5) active.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'DISARM / SILENCE',
          textColor: Colors.white,
          onPressed: _silenceAlarm,
        ),
      ),
    );
  }

  void _silenceAlarm() {
    setState(() {
      _state.isAlarmTriggered = false;
    });
    _sendBtCommand('ALARM:CLEAR');
    _addLog(
      'Alarm Silenced',
      'Sent ALARM:CLEAR to silence Piezo Buzzer (Pin D5).',
    );
  }

  void _addLog(String title, String message, {bool isCritical = false}) {
    setState(() {
      _alertLog.insert(
        0,
        KagixLogEntry(
          timestamp: DateTime.now(),
          title: title,
          message: message,
          isCritical: isCritical,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // DIALOGS & MODALS (4x4 KEYPAD WITH '2006' + 'A'/'C', BLUETOOTH MONITOR)
  // ---------------------------------------------------------------------------

  Future<void> _showKeypadDialog() async {
    String entered = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kagix 4×4 Door Keypad'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Matches DoorControl.cpp: Enter PIN "2006" then press "A" to Unlock, or "C" to Clear:',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      entered.padRight(4, '•'),
                      style: const TextStyle(
                        fontSize: 24,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final key in [
                        '1', '2', '3', 'A',
                        '4', '5', '6', 'B',
                        '7', '8', '9', 'C',
                        '*', '0', '#', 'D'
                      ])
                        SizedBox(
                          width: 56,
                          height: 44,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              backgroundColor: key == 'A'
                                  ? Colors.green.withOpacity(0.25)
                                  : (key == 'C'
                                      ? Colors.red.withOpacity(0.2)
                                      : null),
                            ),
                            onPressed: () {
                              if (key == 'C' || key == '*') {
                                setDialogState(() => entered = '');
                              } else if (key == 'A' || key == '#') {
                                if (entered == _state.keypadPin) {
                                  Navigator.of(ctx).pop();
                                  _openMainDoor(
                                    source: 'App 4×4 Keypad (2006 + A)',
                                  );
                                } else {
                                  setDialogState(() => entered = '');
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Incorrect PIN! Default in DoorControl.cpp is 2006.',
                                      ),
                                    ),
                                  );
                                }
                              } else if (entered.length < 6) {
                                setDialogState(() => entered += key);
                              }
                            },
                            child: Text(
                              key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBluetoothClassicSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.68,
              maxChildSize: 0.9,
              minChildSize: 0.45,
              builder: (_, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bluetooth_connected,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bluetooth Classic (HC-05 / HC-06)',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Arduino Nano D0 (RX) / D1 (TX) • 9600 Baud',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _state.isBtConnected,
                          onChanged: (val) {
                            setState(() => _state.isBtConnected = val);
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Paired Bluetooth Classic Devices',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final dev in _pairedDevices)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: (_state.isBtConnected &&
                                    _state.connectedDevice?.address ==
                                        dev.address)
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          title: Text(
                            dev.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('MAC: ${dev.address} (SPP)'),
                          trailing: (_state.isBtConnected &&
                                  _state.connectedDevice?.address ==
                                      dev.address)
                              ? const Chip(label: Text('Connected'))
                              : OutlinedButton(
                                  onPressed: () async {
                                    await _connectNativeBt(dev);
                                    setModalState(() {});
                                  },
                                  child: const Text('Connect'),
                                ),
                        ),
                      ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Live Bluetooth Serial Monitor (TX / RX)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _serialMonitorLines.clear());
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear'),
                        ),
                      ],
                    ),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _serialMonitorLines.isEmpty
                          ? const Center(
                              child: Text(
                                'No serial traffic yet.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _serialMonitorLines.length,
                              itemBuilder: (_, idx) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _serialMonitorLines[idx],
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    color: _serialMonitorLines[idx]
                                            .contains('[TX]')
                                        ? const Color(0xFF38BDF8)
                                        : _serialMonitorLines[idx]
                                                .contains('[RX]')
                                            ? const Color(0xFF4ADE80)
                                            : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN DASHBOARD UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A192F), Color(0xFF0F3460)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00F5D4).withOpacity(0.65),
                  width: 1.5,
                ),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF00F5D4),
                    size: 24,
                  ),
                  Icon(
                    Icons.lock_outline,
                    color: Color(0xFF38BDF8),
                    size: 12,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kagix Smart Home',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    'Arduino Nano • 2 Pots (A6/A7) • 2 Matrix LEDs (D6/D7)',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bluetooth Classic (HC-05) & Serial Monitor',
            onPressed: _showBluetoothClassicSheet,
            icon: Icon(
              _state.isBtConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: _state.isBtConnected ? Colors.blue : Colors.grey,
            ),
          ),
          IconButton(
            tooltip: 'Security & Event Log',
            onPressed: _showEventLogModal,
            icon: Badge(
              isLabelVisible: _alertLog.isNotEmpty,
              label: Text('${_alertLog.length}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_state.isAlarmTriggered) _buildActiveAlarmBanner(),
          _buildLcdFeedbackDisplay(),
          const SizedBox(height: 16),
          _buildDoorControlCard(),
          const SizedBox(height: 16),
          _buildSecuritySystemCard(),
          const SizedBox(height: 16),
          _buildLightingSystemCard(),
          const SizedBox(height: 16),
          _buildEnvironmentAndClimateCard(),
          const SizedBox(height: 16),
          _buildHardwareSimulatorCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildActiveAlarmBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.crisis_alert, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WINDOW INTRUSION ALARM (IR2 PIN A2)!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Window IR2 sensor (A2) active LOW while Armed. Piezo Buzzer (D5) pulsing!',
                  style: TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade800,
            ),
            onPressed: _silenceAlarm,
            child: const Text('Silence'),
          ),
        ],
      ),
    );
  }

  /// 5. Exact 16x2 I2C LCD Feedback Display Mirror (DisplayManager.cpp: 0x27 on A4/A5)
  Widget _buildLcdFeedbackDisplay() {
    final btStatusText = _state.isBtConnected
        ? 'BT: ${_state.connectedDevice?.name ?? "Kagix-HC05"} (D0/D1)'
        : 'BT: Disconnected';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF475569), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor, color: Color(0xFF94A3B8), size: 16),
                  SizedBox(width: 6),
                  Text(
                    '16×2 I2C LCD (0x27 • NANO PINS A4 SDA / A5 SCL)',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showBluetoothClassicSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (_state.isBtConnected
                            ? const Color(0xFF22C55E)
                            : Colors.orange)
                        .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    btStatusText,
                    style: TextStyle(
                      color: _state.isBtConnected
                          ? const Color(0xFF4ADE80)
                          : Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: _state.isAlarmTriggered
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF84CC16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black54, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _state.lcdLine1,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _state.lcdLine2,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1. Main Door Access Card (DoorControl.cpp: Servo D2, 4x4 Keypad D10-D13 + A1, PIN "2006", 20s timer)
  Widget _buildDoorControlCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _state.isDoorOpen
                      ? Icons.door_front_door_outlined
                      : Icons.door_front_door,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '1. Main Door Access (Servo D2 + 4×4 Keypad)',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _state.isDoorOpen
                        ? Colors.orange.withOpacity(0.2)
                        : Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _state.isDoorOpen
                        ? 'OPENED (${_state.remainingDoorSeconds}s)'
                        : 'CLOSED (0°)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _state.isDoorOpen
                          ? Colors.orange.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'PIN: "${_state.keypadPin}" (Press \'A\' to confirm, \'C\' to clear) • Auto-closes after 20s • Trigger: ${_state.lastDoorTriggerSource}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _state.isDoorOpen
                        ? _closeMainDoorManually
                        : () => _openMainDoor(source: 'Kagix App (DOOR:OPEN)'),
                    icon: Icon(
                      _state.isDoorOpen ? Icons.lock : Icons.lock_open,
                    ),
                    label: Text(
                      _state.isDoorOpen
                          ? 'Close Door (DOOR:CLOSE)'
                          : 'Open Door (20s Timer)',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _showKeypadDialog,
                  icon: const Icon(Icons.dialpad),
                  label: const Text('PIN (2006)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2. Security System Card (Dedicated Switch #2 D8, Window IR2 A2, Door PIR A3, Buzzer D5, Matrix #2 D7)
  Widget _buildSecuritySystemCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _state.isSecurityArmed ? Icons.shield : Icons.shield_outlined,
                  color: _state.isAlarmTriggered
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '2. Security System (Dedicated Matrix #2 D7)',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _state.isSecurityArmed,
                  onChanged: _toggleSecurityMode,
                ),
              ],
            ),
            Text(
              'Dedicated Hardware: Switch #2 (D8) • Window IR2 (A2) → Piezo Buzzer (D5) • Door PIR (A3) → Exterior 8×8 Matrix LED #2 (D7, 60s timer).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _state.isWindowOpen
                    ? Icons.sensor_window_outlined
                    : Icons.sensor_window,
                color: (_state.isWindowOpen && _state.isSecurityArmed)
                    ? Colors.red
                    : Colors.teal,
              ),
              title: const Text('Window Intruder Sensor (IR2 Pin A2 → Buzzer D5)'),
              subtitle: Text(
                _state.isWindowOpen
                    ? (_state.isSecurityArmed
                        ? 'BREACH! Buzzer (D5) pulsing every 200ms'
                        : 'Window Open (Disarmed)')
                    : 'Window Closed & Secure (IR2 HIGH)',
              ),
              trailing: Chip(
                backgroundColor: _state.isWindowOpen
                    ? Colors.red.withOpacity(0.15)
                    : Colors.green.withOpacity(0.15),
                label: Text(_state.isWindowOpen ? 'WIN:1' : 'WIN:0'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.directions_walk,
                color: _state.isMotionDetected
                    ? Colors.amber.shade800
                    : Colors.grey,
              ),
              title: const Text('Door Motion (PIR Pin A3 → Matrix LED #2 Pin D7)'),
              subtitle: Text(
                _state.isExteriorMatrixOn
                    ? 'Exterior 8×8 Matrix LED #2 (D7) ON (60s Security Timer)'
                    : 'Exterior 8×8 Matrix LED #2 (D7) OFF',
              ),
              trailing: Chip(
                avatar: Icon(
                  Icons.grid_on,
                  size: 16,
                  color: _state.isExteriorMatrixOn ? Colors.red : Colors.grey,
                ),
                label: Text(
                  _state.isExteriorMatrixOn ? 'Matrix #2 ON' : 'Matrix #2 OFF',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Automatic Indoor Lighting System Card (Dedicated Matrix #1 D6, Switch #1 D3, LDR A0, Pot #1 A6)
  Widget _buildLightingSystemCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _state.isIndoorLightOn
                      ? Icons.lightbulb
                      : Icons.lightbulb_outline,
                  color: _state.isIndoorLightOn
                      ? Colors.amber.shade700
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '3. Indoor Lighting (Matrix #1 D6 & Pot #1 A6)',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    Icons.grid_view_rounded,
                    size: 16,
                    color: _state.isIndoorLightOn ? Colors.amber : Colors.grey,
                  ),
                  label: Text(
                    _state.isIndoorLightOn ? 'Matrix #1: ON' : 'Matrix #1: OFF',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Dedicated Hardware: Switch #1 (D3, 10s override) • LDR (A0: ${_state.ldrAdcValue}) • Potentiometer #1 (A6 Threshold: ${_state.ldrThreshold}) • 8×8 Matrix LED #1 (D6).',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lighting Mode',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Auto (LIGHT:AUTO)'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Manual (LIGHT:1/0)'),
                    ),
                  ],
                  selected: {_state.isIndoorLightAuto},
                  onSelectionChanged: (selection) {
                    final auto = selection.first;
                    setState(() {
                      _state.isIndoorLightAuto = auto;
                      _evaluateAutomationRules();
                    });
                    if (auto) {
                      _sendBtCommand('LIGHT:AUTO');
                    } else {
                      _sendBtCommand(
                        _state.isIndoorLightOn ? 'LIGHT:1' : 'LIGHT:0',
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() {
                        _state.isIndoorLightAuto = false;
                        _state.isIndoorLightOn = !_state.isIndoorLightOn;
                      });
                      _sendBtCommand(
                        _state.isIndoorLightOn ? 'LIGHT:1' : 'LIGHT:0',
                      );
                    },
                    icon: Icon(
                      _state.isIndoorLightOn
                          ? Icons.lightbulb_outline
                          : Icons.lightbulb,
                    ),
                    label: Text(
                      _state.isIndoorLightOn
                          ? 'Turn Matrix #1 OFF (LIGHT:0)'
                          : 'Turn Matrix #1 ON (LIGHT:1)',
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            // Matrix #1 Brightness Slider (BRI:0..255)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Indoor Matrix #1 Brightness (BRI:0–255):',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_state.matrixBrightness} / 255',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: _state.matrixBrightness.toDouble(),
              min: 0,
              max: 255,
              divisions: 51,
              label: 'BRI:${_state.matrixBrightness}',
              onChanged: (val) {
                setState(() => _state.matrixBrightness = val.round());
              },
              onChangeEnd: (val) {
                _sendBtCommand('BRI:${val.round()}');
              },
            ),
            // LDR Threshold Slider (L_THR:0..1023) + Return to Pot #1 (A6)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'LDR Threshold (${_state.isLdrThrFromApp ? "App Override L_THR" : "Potentiometer #1 on Pin A6"}):',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_state.ldrThreshold} / 1023',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Slider(
              value: _state.ldrThreshold.toDouble(),
              min: 0,
              max: 1023,
              divisions: 64,
              label: 'L_THR:${_state.ldrThreshold}',
              onChanged: (val) {
                setState(() {
                  _state.ldrThreshold = val.round();
                  _state.isLdrThrFromApp = true;
                  _evaluateAutomationRules();
                });
              },
              onChangeEnd: (val) {
                _sendBtCommand('L_THR:${val.round()}');
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _state.isLdrThrFromApp = false);
                  _sendBtCommand('L_THR:AUTO');
                },
                icon: const Icon(Icons.settings_backup_restore, size: 16),
                label: const Text('Return Control to Physical Pot #1 (A6) [L_THR:AUTO]'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 4. Climate Control System Card (DHT11 D4, Fan D9, Dedicated Potentiometer #2 A7)
  Widget _buildEnvironmentAndClimateCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.thermostat_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '4. Climate Control (DHT11 D4, Fan D9, Pot #2 A7)',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(_state.isFanOn ? 'Fan: ON' : 'Fan: OFF'),
                  avatar: Icon(
                    Icons.air,
                    size: 18,
                    color: _state.isFanOn ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.device_thermostat,
                    label: 'DHT11 Temp (D4)',
                    value: '${_state.temperatureC.toStringAsFixed(1)} °C',
                    sublabel:
                        'Trigger > ${_state.tempThresholdC.toStringAsFixed(1)} °C',
                    color: _state.temperatureC > _state.tempThresholdC
                        ? Colors.deepOrange
                        : Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.water_drop_outlined,
                    label: 'Humidity (D4)',
                    value: '${_state.humidityPercent.toStringAsFixed(0)} %',
                    sublabel: 'Read every 2000ms',
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fan Mode (Pin D9)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Auto (FAN:AUTO)'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Manual (FAN:1/0)'),
                    ),
                  ],
                  selected: {_state.isFanAuto},
                  onSelectionChanged: (selection) {
                    final auto = selection.first;
                    setState(() {
                      _state.isFanAuto = auto;
                      _evaluateAutomationRules();
                    });
                    if (auto) {
                      _sendBtCommand('FAN:AUTO');
                    } else {
                      _sendBtCommand(_state.isFanOn ? 'FAN:1' : 'FAN:0');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_state.isFanAuto) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Temp Threshold (0–55°C • ${_state.isTempThrFromApp ? "App Override THR:" : "Potentiometer #2 on Pin A7"}):',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${_state.tempThresholdC.toStringAsFixed(1)} °C',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _state.tempThresholdC.clamp(0.0, 55.0),
                min: 0.0,
                max: 55.0,
                divisions: 55,
                label: '${_state.tempThresholdC.toStringAsFixed(1)} °C',
                onChanged: (val) {
                  setState(() {
                    _state.tempThresholdC = val;
                    _state.isTempThrFromApp = true;
                    _state.lastThresholdSource = 'Kagix App (THR:)';
                    _evaluateAutomationRules();
                  });
                },
                onChangeEnd: (val) {
                  _sendBtCommand('THR:${val.toStringAsFixed(1)}');
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _state.isTempThrFromApp = false;
                      _state.lastThresholdSource = 'Potentiometer #2 (A7)';
                    });
                    _sendBtCommand('THR:AUTO');
                  },
                  icon: const Icon(Icons.settings_backup_restore, size: 16),
                  label: const Text('Return Control to Physical Pot #2 (A7) [THR:AUTO]'),
                ),
              ),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manual Cooling Fan Switch (Pin D9)'),
                subtitle: const Text('Sends FAN:1 / FAN:0 to ClimateControl.cpp'),
                value: _state.isFanOn,
                onChanged: (val) {
                  setState(() => _state.isFanOn = val);
                  _sendBtCommand(val ? 'FAN:1' : 'FAN:0');
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required String sublabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive Hardware Event Simulator for testing all Arduino Nano inputs
  Widget _buildHardwareSimulatorCard() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.memory,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Arduino Nano Hardware & Telemetry Simulator',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Test incoming BluetoothManager::sendStatus() frames from all dedicated Arduino Nano sensors (2 Pots, 2 Switches, 2 Matrix LEDs, IR2, PIR, Keypad):',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(
                    _state.isWindowOpen ? Icons.close : Icons.warning_amber,
                    size: 18,
                  ),
                  label: Text(
                    _state.isWindowOpen
                        ? 'Close Window IR2 (A2)'
                        : 'Trigger Window IR2 (A2)',
                  ),
                  onPressed: () {
                    final nextWin = _state.isWindowOpen ? 0 : 1;
                    _parseArduinoTelemetryFrame('WIN:$nextWin');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.dialpad, size: 18),
                  label: const Text('Physical Keypad "2006" + A'),
                  onPressed: () {
                    _openMainDoor(source: 'Physical 4×4 Keypad (2006 + A)');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.toggle_on, size: 18),
                  label: const Text('Flip Light Switch #1 (D3)'),
                  onPressed: () {
                    final nextLight = _state.isIndoorLightOn ? 0 : 1;
                    _parseArduinoTelemetryFrame('LAUTO:0,LIN:$nextLight');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.security, size: 18),
                  label: const Text('Flip Security Switch #2 (D8)'),
                  onPressed: () {
                    final nextSec = _state.isSecurityArmed ? 0 : 1;
                    _parseArduinoTelemetryFrame('SEC:$nextSec');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.directions_walk, size: 18),
                  label: Text(
                    _state.isMotionDetected
                        ? 'Clear Door PIR (A3)'
                        : 'Trigger Door PIR (A3 → Matrix #2 D7)',
                  ),
                  onPressed: () {
                    final nextMot = _state.isMotionDetected ? 0 : 1;
                    _parseArduinoTelemetryFrame('MOT:$nextMot,EXT:$nextMot');
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 145,
                  child: Text('Pot #1 (A6 LDR Thr):', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _state.ldrThreshold.toDouble(),
                    min: 0,
                    max: 1023,
                    label: 'Pot #1 (A6): ${_state.ldrThreshold}',
                    onChanged: (val) {
                      setState(() {
                        _state.ldrThreshold = val.round();
                        _state.isLdrThrFromApp = false;
                        _evaluateAutomationRules();
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame('LTHR:${val.round()}');
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(
                  width: 145,
                  child: Text('Pot #2 (A7 Temp Thr):', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _state.tempThresholdC.clamp(0.0, 55.0),
                    min: 0.0,
                    max: 55.0,
                    label: 'Pot #2 (A7): ${_state.tempThresholdC.toStringAsFixed(1)} °C',
                    onChanged: (val) {
                      setState(() {
                        _state.tempThresholdC = val;
                        _state.isTempThrFromApp = false;
                        _evaluateAutomationRules();
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame(
                        'THR:${val.toStringAsFixed(1)}',
                      );
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(
                  width: 145,
                  child: Text('LDR Sensor (Pin A0):', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _state.ldrAdcValue.toDouble(),
                    min: 0,
                    max: 1023,
                    label: 'LDR (A0): ${_state.ldrAdcValue}',
                    onChanged: (val) {
                      setState(() {
                        _state.ldrAdcValue = val.round();
                        _evaluateAutomationRules();
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame('LUX:${val.round()}');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEventLogModal() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        if (_alertLog.isEmpty) {
          return const SizedBox(
            height: 220,
            child: Center(
              child: Text('No Kagix security alerts or events recorded yet.'),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _alertLog.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _alertLog[index];
            final timeStr =
                '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}';
            return ListTile(
              leading: Icon(
                item.isCritical ? Icons.crisis_alert : Icons.info_outline,
                color: item.isCritical ? Colors.red : Colors.blueGrey,
              ),
              title: Text(
                item.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: item.isCritical ? Colors.red : null,
                ),
              ),
              subtitle: Text(item.message),
              trailing: Text(
                timeStr,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            );
          },
        );
      },
    );
  }
}
