import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:io';
import 'package:ffi/ffi.dart';

// FFI函数签名定义
typedef UsbCaptureInitC = ffi.Int32 Function();
typedef UsbCaptureInitDart = int Function();

typedef UsbCaptureCleanupC = ffi.Void Function();
typedef UsbCaptureCleanupDart = void Function();

typedef UsbScanDevicesC = ffi.Pointer<ffi.Void> Function();
typedef UsbScanDevicesDart = ffi.Pointer<ffi.Void> Function();

typedef UsbStartCaptureC = ffi.Int32 Function(ffi.Uint16 vendorId, ffi.Uint16 productId);
typedef UsbStartCaptureDart = int Function(int vendorId, int productId);

typedef UsbStopCaptureC = ffi.Int32 Function();
typedef UsbStopCaptureDart = int Function();

typedef UsbGetPacketsC = ffi.Pointer<ffi.Void> Function();
typedef UsbGetPacketsDart = ffi.Pointer<ffi.Void> Function();

typedef UsbGetStatsC = ffi.Pointer<ffi.Void> Function();
typedef UsbGetStatsDart = ffi.Pointer<ffi.Void> Function();

typedef UsbFreeStringC = ffi.Void Function(ffi.Pointer<ffi.Char> s);
typedef UsbFreeStringDart = void Function(ffi.Pointer<ffi.Char> s);

// USB设备信息类
class UsbDeviceInfo {
  final int vendorId;
  final int productId;
  final String vendorName;
  final String productName;
  final String deviceId;

  UsbDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.vendorName,
    required this.productName,
    required this.deviceId,
  });

  factory UsbDeviceInfo.fromJson(Map<String, dynamic> json) {
    return UsbDeviceInfo(
      vendorId: json['vendor_id'] ?? 0,
      productId: json['product_id'] ?? 0,
      vendorName: json['vendor_name'] ?? '未知厂商',
      productName: json['product_name'] ?? '未知产品',
      deviceId: json['device_id'] ?? '未知设备',
    );
  }
}

// USB数据包类
class UsbPacket {
  final DateTime timestamp;
  final int packetType; // 0: receive, 1: send, 2: system
  final String content;
  final int dataLength;

  UsbPacket({
    required this.timestamp,
    required this.packetType,
    required this.content,
    required this.dataLength,
  });

  factory UsbPacket.fromJson(Map<String, dynamic> json) {
    return UsbPacket(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] ?? 0),
      packetType: json['packet_type'] ?? 0,
      content: json['content'] ?? '',
      dataLength: json['data_length'] ?? 0,
    );
  }
}

// 捕获统计信息类
class CaptureStats {
  final int packetCounter;
  final int bytesReceived;
  final int bytesSent;
  final bool isCapturing;

  CaptureStats({
    required this.packetCounter,
    required this.bytesReceived,
    required this.bytesSent,
    required this.isCapturing,
  });

  factory CaptureStats.fromJson(Map<String, dynamic> json) {
    return CaptureStats(
      packetCounter: json['packet_counter'] ?? 0,
      bytesReceived: json['bytes_received'] ?? 0,
      bytesSent: json['bytes_sent'] ?? 0,
      isCapturing: json['is_capturing'] ?? false,
    );
  }
}

// Rust USB捕获库封装类
class UsbCaptureRust {
  static ffi.DynamicLibrary? _lib;
  static UsbCaptureInitDart? _init;
  static UsbCaptureCleanupDart? _cleanup;
  static UsbScanDevicesDart? _scanDevices;
  static UsbStartCaptureDart? _startCapture;
  static UsbStopCaptureDart? _stopCapture;
  static UsbGetPacketsDart? _getPackets;
  static UsbGetStatsDart? _getStats;
  static UsbFreeStringDart? _freeString;

  // 初始化库
  static bool initialize() {
    try {
      if (Platform.isLinux) {
        // 尝试多个可能的路径
        final possiblePaths = [
          'libusb_capture.so',
          './libusb_capture.so',
          '../libusb_capture.so',
          'rust_usb_capture/target/release/libusb_capture.so',
          '../rust_usb_capture/target/release/libusb_capture.so',
        ];
        
        bool loaded = false;
        for (final path in possiblePaths) {
          try {
            _lib = ffi.DynamicLibrary.open(path);
            loaded = true;
            print('成功加载Rust库: $path');
            break;
          } catch (e) {
            print('尝试加载 $path 失败: $e');
            continue;
          }
        }
        
        if (!loaded) {
          print('无法加载Rust动态库，尝试使用绝对路径');
          // 使用当前工作目录的绝对路径
          final currentDir = Directory.current.path;
          final absolutePath = '$currentDir/libusb_capture.so';
          _lib = ffi.DynamicLibrary.open(absolutePath);
        }
      } else if (Platform.isWindows) {
        _lib = ffi.DynamicLibrary.open('usb_capture.dll');
      } else if (Platform.isMacOS) {
        _lib = ffi.DynamicLibrary.open('libusb_capture.dylib');
      } else {
        print('不支持的平台');
        return false;
      }

      _init = _lib!.lookupFunction<UsbCaptureInitC, UsbCaptureInitDart>('usb_capture_init');
      _cleanup = _lib!.lookupFunction<UsbCaptureCleanupC, UsbCaptureCleanupDart>('usb_capture_cleanup');
      _scanDevices = _lib!.lookupFunction<UsbScanDevicesC, UsbScanDevicesDart>('usb_scan_devices');
      _startCapture = _lib!.lookupFunction<UsbStartCaptureC, UsbStartCaptureDart>('usb_start_capture');
      _stopCapture = _lib!.lookupFunction<UsbStopCaptureC, UsbStopCaptureDart>('usb_stop_capture');
      _getPackets = _lib!.lookupFunction<UsbGetPacketsC, UsbGetPacketsDart>('usb_get_packets');
      _getStats = _lib!.lookupFunction<UsbGetStatsC, UsbGetStatsDart>('usb_get_stats');
      _freeString = _lib!.lookupFunction<UsbFreeStringC, UsbFreeStringDart>('usb_free_string');

      final result = _init!();
      if (result != 0) {
        print('USB捕获库初始化失败: $result');
        return false;
      }

      print('USB捕获库初始化成功');
      return true;
    } catch (e) {
      print('加载USB捕获库失败: $e');
      return false;
    }
  }

  // 清理资源
  static void cleanup() {
    _cleanup?.call();
    _lib = null;
  }

  // 扫描USB设备
  static List<UsbDeviceInfo> scanDevices() {
    if (_scanDevices == null) return [];

    try {
      final resultPtr = _scanDevices!();
      if (resultPtr == ffi.nullptr) return [];

      // 将指针转换为字符串
      final jsonString = _pointerToString(resultPtr);
      _freeString?.call(resultPtr.cast<ffi.Char>());

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => UsbDeviceInfo.fromJson(json)).toList();
    } catch (e) {
      print('扫描USB设备失败: $e');
      return [];
    }
  }

  // 开始捕获USB数据
  static bool startCapture(int vendorId, int productId) {
    if (_startCapture == null) return false;

    try {
      final result = _startCapture!(vendorId, productId);
      return result == 0;
    } catch (e) {
      print('开始捕获USB数据失败: $e');
      return false;
    }
  }

  // 停止捕获USB数据
  static bool stopCapture() {
    if (_stopCapture == null) return false;

    try {
      final result = _stopCapture!();
      return result == 0;
    } catch (e) {
      print('停止捕获USB数据失败: $e');
      return false;
    }
  }

  // 获取捕获的数据包
  static List<UsbPacket> getPackets() {
    if (_getPackets == null) return [];

    try {
      final resultPtr = _getPackets!();
      if (resultPtr == ffi.nullptr) return [];

      final jsonString = _pointerToString(resultPtr);
      _freeString?.call(resultPtr.cast());

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => UsbPacket.fromJson(json)).toList();
    } catch (e) {
      print('获取USB数据包失败: $e');
      return [];
    }
  }

  // 获取捕获统计信息
  static CaptureStats? getStats() {
    if (_getStats == null) return null;

    try {
      final resultPtr = _getStats!();
      if (resultPtr == ffi.nullptr) return null;

      final jsonString = _pointerToString(resultPtr);
      _freeString?.call(resultPtr.cast());

      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return CaptureStats.fromJson(jsonMap);
    } catch (e) {
      print('获取捕获统计信息失败: $e');
      return null;
    }
  }

  // 辅助方法：将C字符串指针转换为Dart字符串
  static String _pointerToString(ffi.Pointer<ffi.Void> ptr) {
    if (ptr == ffi.nullptr) return '';
    
    // 将void指针转换为char指针，然后读取字符串
    final charPtr = ptr.cast<ffi.Char>();
    
    // 计算字符串长度
    int length = 0;
    while (charPtr.elementAt(length).value != 0) {
      length++;
    }
    
    // 读取字符串
    final bytes = <int>[];
    for (int i = 0; i < length; i++) {
      bytes.add(charPtr.elementAt(i).value & 0xFF); // 确保字节值在0-255范围内
    }
    
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      print('UTF-8解码失败: $e, 尝试使用Latin1解码');
      return latin1.decode(bytes);
    }
  }
}
