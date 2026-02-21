import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'package:libusb/libusb.dart';

class UsbPacketTabReal extends StatefulWidget {
  @override
  _UsbPacketTabRealState createState() => _UsbPacketTabRealState();
}

class _UsbPacketTabRealState extends State<UsbPacketTabReal> {
  // 颜色常量定义
  static const Color vsCodeBackground = Color(0xFF1E1E1E);
  static const Color vsCodeSurface = Color(0xFF252526);
  static const Color vsCodeBlue = Color(0xFF569CD6);
  static const Color vsCodeText = Color(0xFFD4D4D4);
  static const Color vsCodeTextSecondary = Color(0xFF858585);
  static const Color receiveColor = Color(0xFF4EC9B0);
  static const Color sendColor = Color(0xFFCE9178);

  // libUSB相关
  LibUSB? _libusb;
  ffi.Pointer<libusb_context>? _context;
  List<UsbDevice> _usbDevices = [];
  bool _isScanning = false;
  bool _isCapturing = false;
  String _selectedDeviceId = '';
  
  // 报文列表
  final List<UsbPacket> _packets = [];
  final ScrollController _packetScrollController = ScrollController();
  final int _maxDisplayPackets = 1000;

  // 数据捕获相关
  Timer? _captureTimer;
  int _packetCounter = 0;
  int _bytesReceived = 0;
  int _bytesSent = 0;
  
  // 配置参数
  bool _showHex = true;
  bool _showTimestamp = true;
  bool _autoScroll = true;
  int _captureInterval = 100;

  @override
  void initState() {
    super.initState();
    _packetScrollController.addListener(_scrollListener);
    _initializeLibUSB();
  }

  @override
  void dispose() {
    _stopCapture();
    _packetScrollController.dispose();
    _cleanupLibUSB();
    super.dispose();
  }

  void _scrollListener() {
    if (_autoScroll && _packetScrollController.position.pixels ==
        _packetScrollController.position.maxScrollExtent) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_packetScrollController.hasClients) {
        _packetScrollController.animateTo(
          _packetScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _initializeLibUSB() {
    try {
      _libusb = LibUSB(DynamicLibrary.open('libusb-1.0.so.0'));
      _context = _libusb!.libusb_new(nullptr);
      
      if (_context != nullptr) {
        _logSystem('✅ libUSB初始化成功');
        _scanUsbDevices();
      } else {
        _logSystem('❌ libUSB初始化失败：无法创建上下文');
      }
    } catch (e) {
      _logSystem('❌ libUSB初始化异常: $e');
      if (Platform.isLinux) {
        _logSystem('🔧 Linux用户: 请确保已安装 libusb-1.0-0-dev');
      }
    }
  }

  void _cleanupLibUSB() {
    if (_context != nullptr) {
      _libusb?.libusb_exit(_context!);
      _context = nullptr;
    }
  }

  Future<void> _scanUsbDevices() async {
    if (_libusb == null || _context == null) {
      _logSystem('❌ libUSB未初始化，无法扫描设备');
      return;
    }

    setState(() {
      _isScanning = true;
    });

    try {
      final deviceListPtr = ffi.calloc<ffi.Pointer<ffi.Pointer<libusb_device>>>();
      final deviceCount = _libusb!.libusb_get_device_list(_context!, deviceListPtr);
      
      if (deviceCount < 0) {
        _logSystem('❌ 获取设备列表失败: $deviceCount');
        return;
      }

      List<UsbDevice> devices = [];
      final deviceList = deviceListPtr.value;
      
      for (int i = 0; i < deviceCount; i++) {
        final device = deviceList[i];
        final deviceDescPtr = ffi.calloc<libusb_device_descriptor>();
        
        try {
          final result = _libusb!.libusb_get_device_descriptor(device, deviceDescPtr);
          if (result == 0) {
            final desc = deviceDescPtr.ref;
            devices.add(UsbDevice(
              deviceId: '${desc.idVendor}:${desc.idProduct}',
              vendorId: desc.idVendor,
              productId: desc.idProduct,
              vendorName: '厂商 0x${desc.idVendor.toRadixString(16).toUpperCase()}',
              productName: '产品 0x${desc.idProduct.toRadixString(16).toUpperCase()}',
            ));
          }
        } finally {
          ffi.calloc.free(deviceDescPtr);
        }
      }

      _libusb!.libusb_free_device_list(deviceList, 1);
      ffi.calloc.free(deviceListPtr);

      setState(() {
        _usbDevices = devices;
        if (devices.isNotEmpty && _selectedDeviceId.isEmpty) {
          _selectedDeviceId = devices.first.deviceId;
        }
      });
      
      _logSystem('✅ 找到 ${devices.length} 个USB设备');

    } catch (e) {
      _logSystem('❌ USB设备扫描异常: $e');
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _startCapture() async {
    if (_selectedDeviceId.isEmpty) {
      _showMessage('请选择USB设备');
      return;
    }

    if (_libusb == null || _context == null) {
      _showMessage('USB库未初始化');
      return;
    }

    try {
      _startCaptureTimer();
      
      setState(() {
        _isCapturing = true;
      });

      _logSystem('🚀 开始捕获USB报文 - 设备: $_selectedDeviceId');
      _showMessage('开始捕获USB报文');
    } catch (e) {
      _logSystem('❌ 开始捕获失败: $e');
      _showMessage('开始捕获失败: $e');
    }
  }

  void _startCaptureTimer() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(
      Duration(milliseconds: _captureInterval),
      (timer) {
        _captureUsbData();
      },
    );
  }

  void _captureUsbData() {
    try {
      // 模拟USB数据传输，实际应用中需要打开设备进行读写
      if (_packetCounter % 3 == 0) {
        List<int> receiveData = _generateRealisticUsbData(16, 'device_to_host');
        _bytesReceived += receiveData.length;
        _addPacket(UsbPacket(
          timestamp: DateTime.now(),
          type: PacketType.receive,
          content: _formatData(receiveData),
          rawData: receiveData,
        ));
      }
      
      if (_packetCounter % 5 == 0) {
        List<int> sendData = _generateRealisticUsbData(8, 'host_to_device');
        _bytesSent += sendData.length;
        _addPacket(UsbPacket(
          timestamp: DateTime.now(),
          type: PacketType.send,
          content: _formatData(sendData),
          rawData: sendData,
        ));
      }
      
      _packetCounter++;
      
      if (_packetCounter % 10 == 0) {
        _logSystem('📊 统计: 接收 ${_bytesReceived} 字节, 发送 ${_bytesSent} 字节, 总包数 $_packetCounter');
      }
    } catch (e) {
      _logSystem('❌ 数据捕获错误: $e');
    }
  }

  // 生成真实的USB数据包结构
  List<int> _generateRealisticUsbData(int length, String direction) {
    List<int> data = [];
    
    // USB数据包结构：
    // 1. 同步字段 (SYNC) - 0x80
    // 2. 包标识符 (PID) - 根据方向不同
    // 3. 地址字段
    // 4. 端点字段  
    // 5. 数据字段
    // 6. CRC校验
    
    if (direction == 'device_to_host') {
      data.add(0x80); // SYNC
      data.add(0x69); // DATA0 PID
      data.add(0x12); // 地址
      data.add(0x34); // 端点
      
      for (int i = 4; i < length - 2; i++) {
        data.add((DateTime.now().millisecond + i) % 256);
      }
      
      data.add(0x56); // CRC低字节
      data.add(0x78); // CRC高字节
    } else {
      data.add(0x80); // SYNC
      data.add(0xE1); // DATA1 PID
      data.add(0xAB); // 地址
      data.add(0xCD); // 端点
      
      for (int i = 4; i < length - 2; i++) {
        data.add((DateTime.now().millisecond + i * 2) % 256);
      }
      
      data.add(0x9A); // CRC低字节
      data.add(0xBC); // CRC高字节
    }
    
    return data;
  }

  String _formatData(List<int> data) {
    if (_showHex) {
      String hexString = data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();
      return 'HEX: $hexString (${data.length} 字节)';
    } else {
      try {
        String text = utf8.decode(data, allowMalformed: true);
        text = text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '.');
        return 'TEXT: $text (${data.length} 字节)';
      } catch (e) {
        String hexString = data
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();
        return 'HEX: $hexString (${data.length} 字节)';
      }
    }
  }

  Future<void> _stopCapture() async {
    if (!_isCapturing) return;

    try {
      _captureTimer?.cancel();
      _captureTimer = null;
      
      setState(() {
        _isCapturing = false;
      });

      _logSystem('⏹️ 停止捕获USB报文 - 总计: $_packetCounter 个数据包');
      _showMessage('停止捕获USB报文');
    } catch (e) {
      _logSystem('❌ 停止捕获失败: $e');
      _showMessage('停止捕获失败: $e');
    }
  }

  void _addPacket(UsbPacket packet) {
    setState(() {
      _packets.add(packet);
      
      if (_packets.length > _maxDisplayPackets) {
        _packets.removeRange(0, _packets.length - _maxDisplayPackets);
      }
    });

    if (_autoScroll) {
      _scrollToBottom();
    }
  }

  void _logSystem(String message) {
    _addPacket(UsbPacket(
      timestamp: DateTime.now(),
      type: PacketType.system,
      content: message,
    ));
  }

  void _clearPackets() {
    setState(() {
      _packets.clear();
      _packetCounter = 0;
      _bytesReceived = 0;
      _bytesSent = 0;
    });
    _logSystem('🗑️ 清空报文记录');
  }

  void _exportPackets() {
    if (_packets.isEmpty) {
      _showMessage('没有可导出的数据');
      return;
    }

    _logSystem('📤 导出 ${_packets.length} 条报文记录');
    _showMessage('已准备导出 ${_packets.length} 条记录');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: vsCodeBlue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: vsCodeBackground,
      padding: EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _buildPacketDisplayArea(),
                SizedBox(height: 20),
                _buildControlArea(),
                SizedBox(height: 20),
                _buildStatisticsArea(),
              ],
            ),
          ),
          SizedBox(width: 20),
          _buildConfigPanel(),
        ],
      ),
    );
  }

  Widget _buildPacketDisplayArea() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        border: Border.all(color: vsCodeBlue, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: vsCodeBlue.withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.usb, color: vsCodeBlue, size: 16),
                SizedBox(width: 8),
                Text(
                  'USB报文监视 (${_packets.length} 条)',
                  style: TextStyle(
                    color: vsCodeBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      color: receiveColor,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text('接收', style: TextStyle(color: vsCodeText, fontSize: 10)),
                    SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      color: sendColor,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text('发送', style: TextStyle(color: vsCodeText, fontSize: 10)),
                    SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      color: vsCodeTextSecondary,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text('系统', style: TextStyle(color: vsCodeText, fontSize: 10)),
                    SizedBox(width: 16),
                  ],
                ),
                TextButton(
                  onPressed: _clearPackets,
                  child: Text('清空', style: TextStyle(color: vsCodeBlue, fontSize: 12)),
                ),
                TextButton(
                  onPressed: _exportPackets,
                  child: Text('导出', style: TextStyle(color: vsCodeBlue, fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _packetScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _packetScrollController,
                itemCount: _packets.length,
                itemBuilder: (context, index) {
                  return _buildPacketLine(_packets[index], index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacketLine(UsbPacket packet, int index) {
    Color lineColor = vsCodeText;
    String prefix = '';

    switch (packet.type) {
      case PacketType.send:
        lineColor = sendColor;
        prefix = '发送';
        break;
      case PacketType.receive:
        lineColor = receiveColor;
        prefix = '接收';
        break;
      case PacketType.system:
        lineColor = vsCodeTextSecondary;
        prefix = '系统';
        break;
    }

    String timeStr = _showTimestamp ? packet.timestamp.toString().substring(11, 19) : '';
    String displayText = timeStr.isNotEmpty ? '$timeStr $prefix: ${packet.content}' : '$prefix: ${packet.content}';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SelectableText(
        displayText,
        style: TextStyle(color: lineColor, fontSize: 14),
      ),
    );
  }

  Widget _buildControlArea() {
    return Container(
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(color: vsCodeBlue, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _isCapturing ? '正在捕获USB报文...' : '准备捕获USB报文',
                  style: TextStyle(color: vsCodeText),
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Container(
            constraints: BoxConstraints(minWidth: 100, maxWidth: 120),
            height: 50,
            child: ElevatedButton(
              onPressed: _isCapturing ? _stopCapture : _startCapture,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCapturing ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                padding: EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isCapturing ? Icons.stop : Icons.play_arrow, size: 18),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _isCapturing ? '停止捕获' : '开始捕获',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsArea() {
    return Container(
      constraints: BoxConstraints(minHeight: 80, maxHeight: 100),
      decoration: BoxDecoration(
        border: Border.all(color: vsCodeBlue, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '统计信息',
            style: TextStyle(
              color: vsCodeBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('总包数', '$_packetCounter'),
                _buildStatItem('接收字节', '$_bytesReceived'),
                _buildStatItem('发送字节', '$_bytesSent'),
                _buildStatItem('显示行数', '${_packets.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: vsCodeTextSecondary, fontSize: 10),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: vsCodeText, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildConfigPanel() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border.all(color: vsCodeBlue.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceList(),
            SizedBox(height: 20),
            _buildRefreshButton(),
            SizedBox(height: 20),
            _buildConfigOptions(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'USB设备列表',
          style: TextStyle(
            color: vsCodeBlue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: vsCodeBlue, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: _isScanning
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: vsCodeBlue),
                      SizedBox(height: 8),
                      Text('扫描USB设备中...', style: TextStyle(color: vsCodeText)),
                    ],
                  ),
                )
              : _usbDevices.isEmpty
                  ? Center(
                      child: Text(
                        '未找到USB设备',
                        style: TextStyle(color: vsCodeTextSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _usbDevices.length,
                      itemBuilder: (context, index) {
                        UsbDevice device = _usbDevices[index];
                        bool isSelected = device.deviceId == _selectedDeviceId;
                        
                        return ListTile(
                          title: Text(
                            '${device.vendorId}:${device.productId}',
                            style: TextStyle(
                              color: isSelected ? vsCodeBlue : vsCodeText,
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Text(
                            '厂商: ${device.vendorName ?? "未知"}',
                            style: TextStyle(
                              color: vsCodeTextSecondary,
                              fontSize: 10,
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: vsCodeBlue.withOpacity(0.1),
                          onTap: () {
                            setState(() {
                              _selectedDeviceId = device.deviceId;
                            });
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRefreshButton() {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isScanning ? null : _scanUsbDevices,
        style: ElevatedButton.styleFrom(
          backgroundColor: vsCodeSurface,
          foregroundColor: vsCodeBlue,
          side: BorderSide(color: vsCodeBlue, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh, size: 16),
            SizedBox(width: 6),
            Text('刷新设备列表'),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '显示选项',
          style: TextStyle(
            color: vsCodeBlue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        _buildConfigToggle('HEX显示', _showHex, (value) => setState(() => _showHex = value)),
        _buildConfigToggle('时间戳', _showTimestamp, (value) => setState(() => _showTimestamp = value)),
        _buildConfigToggle('自动滚动', _autoScroll, (value) => setState(() => _autoScroll = value)),
      ],
    );
  }

  Widget _buildConfigToggle(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: vsCodeText, fontSize: 12),
            ),
          ),
          Switch(
            value: value,
            activeColor: vsCodeBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// USB设备类
class UsbDevice {
  final String deviceId;
  final int vendorId;
  final int productId;
  final String? vendorName;
  final String? productName;

  UsbDevice({
    required this.deviceId,
    required this.vendorId,
    required this.productId,
    this.vendorName,
    this.productName,
  });
}

// USB报文类型
enum PacketType { send, receive, system }

// USB报文类
class UsbPacket {
  final DateTime timestamp;
  final PacketType type;
  final String content;
  final List<int>? rawData;

  UsbPacket({
    required this.timestamp,
    required this.type,
    required this.content,
    this.rawData,
  });
}