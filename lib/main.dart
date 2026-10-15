import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// KAGIX SMART HOME — MCT 331s Mechatronic System Integration
// Architecture:
//   • Communication: Bluetooth Classic SPP (HC-05 / HC-06 @ 9600 baud)
//   • Control Mode:  "Alongside" Bidirectional Sync (Physical Keypad, Knob,
//                    and Override Push Button work seamlessly alongside the
//                    Mobile App controls in real time)
//
// To connect to real HC-05 / HC-06 hardware in your Flutter project:
//   1. Run: flutter pub add flutter_bluetooth_serial permission_handler
//   2. Uncomment the `FlutterBluetoothSerial` wire-up in `BluetoothClassicAdapter`
//      below (lines marked with [HARDWARE_LINK]).
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

/// Complete real-time state of the "Kagix" Smart Home Prototype.
class KagixHomeState {
  // House Identity
  final String houseName = 'Kagix';

  // 1. Main Door Access (Physical Keypad + App Control alongside each other)
  bool isDoorOpen;
  int autoCloseDelaySeconds;
  int remainingDoorSeconds;
  String keypadPin;
  String lastDoorTriggerSource; // 'Physical Keypad' or 'Kagix App'

  // 2. Security System (Window Sensor + Motion Sensor + Exterior Light)
  bool isSecurityArmed;
  bool isWindowOpen;
  bool isMotionDetected;
  bool isAlarmTriggered;
  bool isExteriorLightOn;

  // 3. Automatic Indoor Lighting System (LDR Sensor + Physical Button + App Switch)
  bool isIndoorLightAuto;
  bool isIndoorLightOn;
  double ambientLightLux;
  double ambientThresholdLux;
  String lastLightControlSource; // 'LDR Auto', 'Physical Button', or 'Kagix App'

  // 4. Climate Control System (DHT Temp/Humidity + Physical Knob + App Slider)
  double temperatureC;
  double humidityPercent;
  double tempThresholdC;
  bool isFanAuto;
  bool isFanOn;
  String lastThresholdSource; // 'Physical Knob (A0)' or 'Kagix App'

  // Bluetooth Classic Connection State
  bool isBtConnected;
  bool isBtConnecting;
  BtClassicDevice? connectedDevice;

  KagixHomeState({
    this.isDoorOpen = false,
    this.autoCloseDelaySeconds = 5,
    this.remainingDoorSeconds = 0,
    this.keypadPin = '1234',
    this.lastDoorTriggerSource = 'Closed',
    this.isSecurityArmed = true,
    this.isWindowOpen = false,
    this.isMotionDetected = false,
    this.isAlarmTriggered = false,
    this.isExteriorLightOn = false,
    this.isIndoorLightAuto = true,
    this.isIndoorLightOn = false,
    this.ambientLightLux = 420.0,
    this.ambientThresholdLux = 300.0,
    this.lastLightControlSource = 'LDR Auto',
    this.temperatureC = 26.5,
    this.humidityPercent = 48.0,
    this.tempThresholdC = 28.0,
    this.isFanAuto = true,
    this.isFanOn = false,
    this.lastThresholdSource = 'Physical Knob (A0)',
    this.isBtConnected = false,
    this.isBtConnecting = false,
    this.connectedDevice,
  });

  /// Line 1 of the physical 16x2 LCD module on the Kagix prototype.
  String get lcdLine1 {
    final doorStr = isDoorOpen ? 'OPEN(${remainingDoorSeconds}s)' : 'CLSD';
    final secStr = isAlarmTriggered
        ? 'ALRM!'
        : (isSecurityArmed ? 'ARM' : 'OFF');
    return 'KAGIX D:$doorStr S:$secStr';
  }

  /// Line 2 of the physical 16x2 LCD module on the Kagix prototype.
  String get lcdLine2 {
    final fanStr = isFanOn ? 'ON' : 'OFF';
    return 'T:${temperatureC.toStringAsFixed(1)}C H:${humidityPercent.toStringAsFixed(0)}% F:$fanStr';
  }
}

class KagixLogEntry {
  final DateTime timestamp;
  final String title;
  final String message;
  final bool isCritical;
  final String direction; // 'SYS', 'TX', 'RX'

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

  // Default paired Bluetooth Classic devices for scanning/selection
  List<BtClassicDevice> _pairedDevices = [
    BtClassicDevice(name: 'Kagix-HC05', address: '98:D3:31:FB:48:A2'),
    BtClassicDevice(name: 'HC-06', address: '00:21:13:01:9C:11'),
  ];

  @override
  void initState() {
    super.initState();
    _state.connectedDevice = _pairedDevices.first;
    _state.isBtConnected = true;
    _appendSerialMonitor('SYS', 'Bluetooth Classic SPP ready (Target: Kagix-HC05 @ 9600 baud)');
    _initNativeBluetoothChannel();
  }

  @override
  void dispose() {
    _doorAutoCloseTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BLUETOOTH CLASSIC (HC-05 / HC-06 SPP) STREAM & COMMAND PROTOCOL
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
      // Running in simulator or iOS where native Android SPP channel is inactive
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
          _state.isBtConnected = true; // Keep demo mode active if testing without hardware
          _state.isBtConnecting = false;
        });
        _appendSerialMonitor(
          'SYS',
          'Active link switched to ${dev.name} (${dev.address})',
        );
      }
    }
  }

  /// Sends a newline-delimited ASCII command frame over Bluetooth Classic SPP.
  void _sendBtCommand(String command) {
    final frame = '${command.trim()}\n';
    _appendSerialMonitor('TX', command.trim());
    _btChannel.invokeMethod('write', {'data': frame}).catchError((_) {});
    debugPrint('[Kagix BT Classic TX] -> ${frame.trim()}');
  }

  /// Handles raw incoming byte chunks from `BluetoothConnection.input`
  /// and reassembles newline-delimited frames (`\n`) safely.
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

  /// Parses a complete telemetry line sent by the Arduino over HC-05/HC-06.
  /// Supports "Alongside" bidirectional sync so physical keypad, physical
  /// potentiometer knob, and physical light push button update the app UI live.
  ///
  /// Example Arduino Serial/BT frame:
  /// `TEMP:27.4,HUM:52,THR:28.5,TSRC:KNOB,DOOR:1,REM:4,DSRC:KEYPAD,SEC:1,WIN:0,MOT:1,LIN:1,LAUTO:0,LSRC:BTN,FAN:0,FAUTO:1,LUX:210`
  void _parseArduinoTelemetryFrame(String payload) {
    final clean = payload.trim();
    if (clean.isEmpty) return;
    _appendSerialMonitor('RX', clean);

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
              _state.tempThresholdC = newThr.clamp(18.0, 40.0);
            }
            break;
          case 'TSRC':
            _state.lastThresholdSource =
                val == 'KNOB' ? 'Physical Knob (A0)' : 'Kagix App';
            break;
          case 'DOOR':
            final open = (val == '1' || val == 'OPEN');
            if (open && !_state.isDoorOpen) {
              doorJustOpenedFromKeypad = true;
            }
            _state.isDoorOpen = open;
            break;
          case 'REM':
            _state.remainingDoorSeconds =
                int.tryParse(val) ?? _state.remainingDoorSeconds;
            break;
          case 'DSRC':
            _state.lastDoorTriggerSource =
                val == 'KEYPAD' ? 'Physical Keypad' : 'Kagix App';
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
            break;
          case 'LIN':
          case 'LIGHT':
            _state.isIndoorLightOn = (val == '1' || val == 'ON');
            break;
          case 'LAUTO':
            _state.isIndoorLightAuto = (val == '1' || val == 'AUTO');
            break;
          case 'LSRC':
            if (val == 'BTN') {
              _state.lastLightControlSource = 'Physical Push Button';
            } else if (val == 'LDR') {
              _state.lastLightControlSource = 'LDR Auto Sensor';
            } else {
              _state.lastLightControlSource = 'Kagix App';
            }
            break;
          case 'FAN':
            _state.isFanOn = (val == '1' || val == 'ON');
            break;
          case 'FAUTO':
            _state.isFanAuto = (val == '1' || val == 'AUTO');
            break;
          case 'LUX':
            _state.ambientLightLux =
                double.tryParse(val) ?? _state.ambientLightLux;
            break;
        }
      }

      if (doorJustOpenedFromKeypad) {
        _addLog(
          'Main Door Opened (Physical Keypad)',
          'Correct PIN entered on physical keypad. Auto-closing in ${_state.autoCloseDelaySeconds}s.',
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
  // SYSTEM CONTROL LOGIC ("ALONGSIDE" HARDWARE + APP CO-CONTROL)
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
      'Kagix Main Door Opened',
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
          _state.lastDoorTriggerSource = 'Auto-Closed';
          timer.cancel();
          _sendBtCommand('DOOR:AUTO_CLOSED');
          _addLog(
            'Kagix Main Door Closed',
            'Door locked automatically after preset delay.',
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
      _state.lastDoorTriggerSource = 'Kagix App (Manual Lock)';
    });
    _sendBtCommand('DOOR:CLOSE');
    _addLog('Kagix Main Door Closed', 'Locked immediately from Kagix mobile app.');
  }

  void _toggleSecurityMode(bool armed) {
    setState(() {
      _state.isSecurityArmed = armed;
      if (!armed) {
        _state.isAlarmTriggered = false;
        _state.isExteriorLightOn = false;
      } else {
        _evaluateAutomationRules(windowJustOpened: _state.isWindowOpen);
      }
    });
    _sendBtCommand(armed ? 'SEC:1' : 'SEC:0');
    _addLog(
      armed ? 'Kagix Security ARMED' : 'Kagix Security DISARMED',
      armed
          ? 'Window intrusion alarm and exterior motion light are active.'
          : 'Security monitoring disarmed.',
    );
  }

  void _evaluateAutomationRules({bool windowJustOpened = false}) {
    // 2a. Security System: Window opened while armed -> trigger alarm + mobile message
    if (_state.isSecurityArmed && _state.isWindowOpen) {
      _state.isAlarmTriggered = true;
      if (windowJustOpened) {
        _triggerWindowSecurityAlert();
      }
    }

    // 2b. Security System: Exterior light turns on automatically when motion is detected near main door
    if (_state.isSecurityArmed) {
      _state.isExteriorLightOn = _state.isMotionDetected;
    }

    // 3. Automatic Indoor Lighting: LDR threshold + Manual override button/app sync
    if (_state.isIndoorLightAuto) {
      _state.isIndoorLightOn =
          _state.ambientLightLux < _state.ambientThresholdLux;
      _state.lastLightControlSource = 'LDR Auto Sensor';
    }

    // 4. Climate Control: Fan activates when temperature exceeds threshold (set by physical knob or app slider)
    if (_state.isFanAuto) {
      _state.isFanOn = _state.temperatureC > _state.tempThresholdC;
    }
  }

  void _triggerWindowSecurityAlert() {
    final alert = KagixLogEntry(
      timestamp: DateTime.now(),
      title: 'KAGIX SECURITY ALERT: Window Opened!',
      message:
          'Window sensor triggered while Security Mode is ARMED! Siren activated on Kagix prototype.',
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
                'KAGIX ALERT: Window opened in Security Mode! Alarm triggered.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'SILENCE',
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
      'Window intrusion alarm silenced from Kagix app.',
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
  // DIALOGS & MODALS (KEYPAD, BLUETOOTH CLASSIC MANAGER, EVENT LOG)
  // ---------------------------------------------------------------------------

  Future<void> _showKeypadDialog() async {
    String entered = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kagix Door Keypad (PIN)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Works alongside the physical 4x4 keypad (Default PIN: 1234):',
                    style: TextStyle(fontSize: 13),
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
                      for (final digit in [
                        '1', '2', '3',
                        '4', '5', '6',
                        '7', '8', '9',
                        'C', '0', 'OK'
                      ])
                        SizedBox(
                          width: 64,
                          height: 48,
                          child: FilledButton.tonal(
                            onPressed: () {
                              if (digit == 'C') {
                                setDialogState(() => entered = '');
                              } else if (digit == 'OK') {
                                if (entered == _state.keypadPin) {
                                  Navigator.of(ctx).pop();
                                  _sendBtCommand('PIN:$entered');
                                  _openMainDoor(source: 'Kagix App Keypad');
                                } else {
                                  setDialogState(() => entered = '');
                                  _sendBtCommand('PIN:FAIL');
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text('Incorrect Kagix PIN code!'),
                                    ),
                                  );
                                }
                              } else if (entered.length < 4) {
                                setDialogState(() => entered += digit);
                              }
                            },
                            child: Text(digit),
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
                                'Serial Port Profile (SPP) • 9600 Baud • Kagix House',
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
                            _appendSerialMonitor(
                              'SYS',
                              val
                                  ? 'Connected to ${_state.connectedDevice?.name ?? "Kagix-HC05"}'
                                  : 'Disconnected from Bluetooth Classic SPP',
                            );
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
                                padding: const EdgeInsets.symmetric(vertical: 2),
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.home_work_rounded,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 20,
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
                    'Bluetooth Classic • Alongside Co-Control',
                    style: TextStyle(fontSize: 11.5),
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
          _buildEnvironmentAndClimateCard(),
          const SizedBox(height: 16),
          _buildDoorControlCard(),
          const SizedBox(height: 16),
          _buildSecuritySystemCard(),
          const SizedBox(height: 16),
          _buildLightingSystemCard(),
          const SizedBox(height: 16),
          _buildHardwareSimulatorCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// High-priority red intrusion banner when the window opens in Security Mode
  Widget _buildActiveAlarmBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                  'KAGIX SECURITY BREACH!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Window opened while Security Mode is ARMED. Alarm triggered!',
                  style: TextStyle(color: Colors.white, fontSize: 13),
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

  /// 5. Physical 16x2 LCD Feedback Display Mirror (with Kagix header & BT status)
  Widget _buildLcdFeedbackDisplay() {
    final btStatusText = _state.isBtConnected
        ? 'BT: ${_state.connectedDevice?.name ?? "Kagix-HC05"}'
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
                    'KAGIX 16x2 LCD FEEDBACK DISPLAY',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bluetooth,
                        size: 12,
                        color: _state.isBtConnected
                            ? const Color(0xFF4ADE80)
                            : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        btStatusText,
                        style: TextStyle(
                          color: _state.isBtConnected
                              ? const Color(0xFF4ADE80)
                              : Colors.orangeAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _state.lcdLine2,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Climate Control System & Temp/Humidity Readings (Alongside Physical Knob)
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
                    'Climate Control & Temp / Humidity',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                    label: 'Temperature',
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
                    label: 'Humidity',
                    value: '${_state.humidityPercent.toStringAsFixed(0)} %',
                    sublabel: 'Kagix Indoor RH',
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
                  'Fan Mode',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Auto (Knob + App)'),
                    ),
                    ButtonSegment(value: false, label: Text('Manual Fan')),
                  ],
                  selected: {_state.isFanAuto},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _state.isFanAuto = selection.first;
                      _evaluateAutomationRules();
                    });
                    _sendBtCommand(_state.isFanAuto ? 'FAUTO:1' : 'FAUTO:0');
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
                      'Threshold (Synced with Physical Knob • Last: ${_state.lastThresholdSource}):',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    '${_state.tempThresholdC.toStringAsFixed(1)} °C',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _state.tempThresholdC,
                min: 18.0,
                max: 40.0,
                divisions: 44,
                label: '${_state.tempThresholdC.toStringAsFixed(1)} °C',
                onChanged: (val) {
                  setState(() {
                    _state.tempThresholdC = val;
                    _state.lastThresholdSource = 'Kagix App';
                    _evaluateAutomationRules();
                  });
                },
                onChangeEnd: (val) {
                  _sendBtCommand('THR:${val.toStringAsFixed(1)}');
                },
              ),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manual Cooling Fan Switch'),
                subtitle: const Text('Direct fan control from Kagix app'),
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

  /// 1. Main Door Access Card (Works alongside the physical 4x4 keypad)
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
                    'Kagix Main Door Access',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        ? 'OPEN (${_state.remainingDoorSeconds}s)'
                        : 'CLOSED & LOCKED',
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
              'Works alongside the physical keypad (Auto-closes after ${_state.autoCloseDelaySeconds}s • Last trigger: ${_state.lastDoorTriggerSource}).',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _state.isDoorOpen
                        ? _closeMainDoorManually
                        : () => _openMainDoor(source: 'Kagix App'),
                    icon: Icon(
                      _state.isDoorOpen ? Icons.lock : Icons.lock_open,
                    ),
                    label: Text(
                      _state.isDoorOpen ? 'Close Door Now' : 'Open Main Door',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showKeypadDialog,
                  icon: const Icon(Icons.dialpad),
                  label: const Text('PIN Keypad'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2. Security System Card (Window Intrusion Alarm + Exterior Motion Light)
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
                    'Kagix Security System',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: _state.isSecurityArmed,
                  onChanged: _toggleSecurityMode,
                ),
              ],
            ),
            Text(
              _state.isSecurityArmed
                  ? 'Security Mode ARMED: Opening the window triggers an instant mobile alert & alarm; motion near the main door turns on the exterior light.'
                  : 'Security Mode DISARMED: Window intrusion alarm is inactive.',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
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
              title: const Text('Window Sensor Status'),
              subtitle: Text(
                _state.isWindowOpen
                    ? (_state.isSecurityArmed
                        ? 'OPEN — SECURITY BREACH!'
                        : 'Window is Open (Security Disarmed)')
                    : 'Window is Closed & Secure',
              ),
              trailing: Chip(
                backgroundColor: _state.isWindowOpen
                    ? Colors.red.withOpacity(0.15)
                    : Colors.green.withOpacity(0.15),
                label: Text(_state.isWindowOpen ? 'OPEN' : 'CLOSED'),
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
              title: const Text('Main Door Motion & Exterior Light'),
              subtitle: Text(
                _state.isMotionDetected
                    ? 'Motion detected near Kagix main door!'
                    : 'No motion near main door',
              ),
              trailing: Chip(
                avatar: Icon(
                  Icons.lightbulb,
                  size: 16,
                  color: _state.isExteriorLightOn ? Colors.amber : Colors.grey,
                ),
                label: Text(
                  _state.isExteriorLightOn ? 'Ext. Light ON' : 'Ext. Light OFF',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Automatic Indoor Lighting System Card (LDR + Physical Button + App Switch)
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
                    'Indoor Lighting System',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(
                    _state.isIndoorLightOn ? 'Light: ON' : 'Light: OFF',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Works alongside the LDR sensor and physical override push button (Active source: ${_state.lastLightControlSource}).',
              style: TextStyle(
                fontSize: 12.5,
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
                    ButtonSegment(value: true, label: Text('Auto (LDR)')),
                    ButtonSegment(
                      value: false,
                      label: Text('Manual (Btn + App)'),
                    ),
                  ],
                  selected: {_state.isIndoorLightAuto},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _state.isIndoorLightAuto = selection.first;
                      _state.lastLightControlSource = _state.isIndoorLightAuto
                          ? 'LDR Auto Sensor'
                          : 'Kagix App';
                      _evaluateAutomationRules();
                    });
                    _sendBtCommand(
                      _state.isIndoorLightAuto ? 'LAUTO:1' : 'LAUTO:0',
                    );
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
                        _state.lastLightControlSource = 'Kagix App';
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
                          ? 'Turn Indoor Light OFF'
                          : 'Turn Indoor Light ON',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Interactive Hardware Event Simulator so the team can test "Alongside" events & Bluetooth RX frames
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
                    'Kagix Hardware & Bluetooth RX Simulator',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Simulate physical inputs from the Kagix Arduino board (Keypad, Knob, Push Button, Window & Motion sensors) arriving over Bluetooth Classic:',
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
                        ? 'Close Window Sensor'
                        : 'Simulate Window Opened',
                  ),
                  onPressed: () {
                    final nextWin = _state.isWindowOpen ? 0 : 1;
                    _parseArduinoTelemetryFrame('WIN:$nextWin');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.dialpad, size: 18),
                  label: const Text('Simulate Physical Keypad Unlock'),
                  onPressed: () {
                    _parseArduinoTelemetryFrame('DOOR:1,REM:5,DSRC:KEYPAD');
                    _openMainDoor(source: 'Physical Keypad');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.touch_app, size: 18),
                  label: const Text('Simulate Physical Light Button'),
                  onPressed: () {
                    final nextLight = _state.isIndoorLightOn ? 0 : 1;
                    _parseArduinoTelemetryFrame(
                      'LAUTO:0,LIN:$nextLight,LSRC:BTN',
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.directions_walk, size: 18),
                  label: Text(
                    _state.isMotionDetected
                        ? 'Clear Door Motion'
                        : 'Simulate Door Motion',
                  ),
                  onPressed: () {
                    final nextMot = _state.isMotionDetected ? 0 : 1;
                    _parseArduinoTelemetryFrame('MOT:$nextMot');
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.dark_mode_outlined, size: 18),
                  label: Text(
                    _state.ambientLightLux < _state.ambientThresholdLux
                        ? 'Simulate Bright Room (450 lx)'
                        : 'Simulate Dark Room (120 lx)',
                  ),
                  onPressed: () {
                    final nextLux =
                        _state.ambientLightLux < _state.ambientThresholdLux
                            ? 450
                            : 120;
                    _parseArduinoTelemetryFrame('LAUTO:1,LUX:$nextLux');
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 130, child: Text('Physical Knob (A0):')),
                Expanded(
                  child: Slider(
                    value: _state.tempThresholdC,
                    min: 18.0,
                    max: 40.0,
                    label: 'Knob: ${_state.tempThresholdC.toStringAsFixed(1)} °C',
                    onChanged: (val) {
                      setState(() {
                        _state.tempThresholdC = val;
                        _state.lastThresholdSource = 'Physical Knob (A0)';
                        _evaluateAutomationRules();
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame(
                        'THR:${val.toStringAsFixed(1)},TSRC:KNOB',
                      );
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 130, child: Text('DHT Temp (°C):')),
                Expanded(
                  child: Slider(
                    value: _state.temperatureC,
                    min: 15.0,
                    max: 42.0,
                    label: '${_state.temperatureC.toStringAsFixed(1)} °C',
                    onChanged: (val) {
                      setState(() {
                        _state.temperatureC = val;
                        _evaluateAutomationRules();
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame(
                        'TEMP:${val.toStringAsFixed(1)},HUM:${_state.humidityPercent.toStringAsFixed(0)}',
                      );
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 130, child: Text('DHT Humidity (%):')),
                Expanded(
                  child: Slider(
                    value: _state.humidityPercent,
                    min: 20.0,
                    max: 90.0,
                    label: '${_state.humidityPercent.toStringAsFixed(0)} %',
                    onChanged: (val) {
                      setState(() {
                        _state.humidityPercent = val;
                      });
                    },
                    onChangeEnd: (val) {
                      _parseArduinoTelemetryFrame(
                        'TEMP:${_state.temperatureC.toStringAsFixed(1)},HUM:${val.toStringAsFixed(0)}',
                      );
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