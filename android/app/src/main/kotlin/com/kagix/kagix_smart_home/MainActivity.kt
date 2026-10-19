package com.kagix.kagix_smart_home

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.kagix.smarthome/bt_classic"
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var btSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    @Volatile private var isReading = false
    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    if (hasBtPermissions()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        requestBtPermissions()
                    }
                }
                "getPairedDevices" -> {
                    if (!hasBtPermissions()) {
                        requestBtPermissions()
                        result.success(emptyList<Map<String, String>>())
                    } else {
                        result.success(getBondedDevicesList())
                    }
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address.isNullOrEmpty()) {
                        result.error("INVALID_ARG", "Bluetooth MAC address required", null)
                    } else {
                        connectToDevice(address, result)
                    }
                }
                "disconnect" -> {
                    disconnectSocket()
                    result.success(true)
                }
                "write" -> {
                    val data = call.argument<String>("data") ?: ""
                    result.success(writeToSocket(data))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasBtPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectPerm = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            val scanPerm = checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)
            return connectPerm == PackageManager.PERMISSION_GRANTED &&
                    scanPerm == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    private fun requestBtPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN
                ),
                1001
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevicesList(): List<Map<String, String>> {
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter: BluetoothAdapter? = btManager?.adapter
        val list = mutableListOf<Map<String, String>>()
        val bonded: Set<BluetoothDevice>? = adapter?.bondedDevices
        bonded?.forEach { device ->
            list.add(
                mapOf(
                    "name" to (device.name ?: "Unknown BT"),
                    "address" to (device.address ?: "")
                )
            )
        }
        return list
    }

    @SuppressLint("MissingPermission")
    private fun connectToDevice(address: String, result: MethodChannel.Result) {
        thread {
            try {
                disconnectSocket()
                val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter: BluetoothAdapter? = btManager?.adapter
                val device = adapter?.getRemoteDevice(address)
                    ?: throw Exception("Bluetooth device not found: $address")

                adapter.cancelDiscovery()

                // 3-Stage RFCOMM Connection Strategy (same as Serial Bluetooth Terminal for HC-05/HC-06):
                // 1) Standard secure RFCOMM socket
                // 2) Insecure RFCOMM socket
                // 3) Channel 1 reflection fallback for Chinese HC-05 clones
                var connectedSocket: BluetoothSocket? = null
                var lastErr: Exception? = null

                try {
                    val s1 = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    s1.connect()
                    connectedSocket = s1
                } catch (e1: Exception) {
                    lastErr = e1
                    try {
                        val s2 = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                        s2.connect()
                        connectedSocket = s2
                    } catch (e2: Exception) {
                        lastErr = e2
                        try {
                            val m = device.javaClass.getMethod(
                                "createRfcommSocket",
                                Int::class.javaPrimitiveType
                            )
                            val s3 = m.invoke(device, 1) as BluetoothSocket
                            s3.connect()
                            connectedSocket = s3
                        } catch (e3: Exception) {
                            lastErr = e3
                        }
                    }
                }

                if (connectedSocket == null || !connectedSocket.isConnected) {
                    throw lastErr ?: Exception("RFCOMM connect failed")
                }

                btSocket = connectedSocket
                outputStream = connectedSocket.outputStream
                isReading = true
                startReadingLoop(connectedSocket.inputStream)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                disconnectSocket()
                mainHandler.post {
                    result.error("CONNECT_FAIL", e.message ?: "RFCOMM connect failed", null)
                }
            }
        }
    }

    private fun startReadingLoop(inputStream: InputStream?) {
        if (inputStream == null) return
        thread {
            val buffer = ByteArray(1024)
            while (isReading) {
                try {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead > 0) {
                        val chunk = String(buffer, 0, bytesRead, Charsets.UTF_8)
                        mainHandler.post {
                            methodChannel?.invokeMethod("onDataReceived", chunk)
                        }
                    } else if (bytesRead == -1) {
                        break
                    }
                } catch (_: Exception) {
                    break
                }
            }
            isReading = false
            mainHandler.post {
                methodChannel?.invokeMethod("onDisconnected", null)
            }
        }
    }

    private fun writeToSocket(data: String): Boolean {
        return try {
            outputStream?.write(data.toByteArray(Charsets.UTF_8))
            outputStream?.flush()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun disconnectSocket() {
        isReading = false
        try {
            outputStream?.close()
        } catch (_: Exception) {}
        try {
            btSocket?.close()
        } catch (_: Exception) {}
        outputStream = null
        btSocket = null
    }
}