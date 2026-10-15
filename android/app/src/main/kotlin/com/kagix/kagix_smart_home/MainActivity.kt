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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    ensureBtPermissions()
                    result.success(true)
                }
                "getPairedDevices" -> {
                    if (!ensureBtPermissions()) {
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

    private fun ensureBtPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val connectPerm = checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
            val scanPerm = checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN)
            if (connectPerm != PackageManager.PERMISSION_GRANTED ||
                scanPerm != PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.BLUETOOTH_CONNECT,
                        Manifest.permission.BLUETOOTH_SCAN
                    ),
                    1001
                )
                return false
            }
        }
        return true
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
                val socket = device?.createRfcommSocketToServiceRecord(SPP_UUID)
                adapter?.cancelDiscovery()
                socket?.connect()
                btSocket = socket
                outputStream = socket?.outputStream
                isReading = true
                startReadingLoop(socket?.inputStream)
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
