import 'dart:async';
import 'dart:convert';
import 'dart:io'; // <-- 新增，用于调用外部进程(esptool)
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fl_chart/fl_chart.dart';
import 'websocket_server.dart';
import 'websocket_panel.dart';
import 'websocket_control_page.dart';

void main() {
  // 在运行应用之前，确保插件系统已初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  print('启动通信工具应用 - 使用Rust USB捕获实现');
  
  runApp(CommunicationToolApp());
}

class CommunicationToolApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '通信工具',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFF569CD6),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF569CD6),
          secondary: const Color(0xFFCE9178),
          surface: const Color(0xFF252526),
          background: const Color(0xFF1E1E1E),
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    // 修改为3个页面
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Color(0xFF1E1E1E),
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: NavigationRailLabelType.selected,
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.settings_input_component, color: Color(0xFF858585)),
                selectedIcon: Icon(Icons.settings_input_component, color: Color(0xFF569CD6)),
                label: Text('串口通信', style: TextStyle(color: Color(0xFF858585))),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.network_wifi, color: Color(0xFF858585)),
                selectedIcon: Icon(Icons.network_wifi, color: Color(0xFF569CD6)),
                label: Text('WebSocket控制', style: TextStyle(color: Color(0xFF858585))),
              ),
              // ====== 新增：固件烧录侧边栏导航 ======
              NavigationRailDestination(
                icon: Icon(Icons.memory, color: Color(0xFF858585)),
                selectedIcon: Icon(Icons.memory, color: Color(0xFF569CD6)),
                label: Text('固件烧录', style: TextStyle(color: Color(0xFF858585))),
              ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                SerialPortHomePage(),
                WebSocketControlPage(),
                // ====== 新增：固件烧录页面视图 ======
                FirmwareFlashPage(), 
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SerialPortHomePage extends StatefulWidget {
  static _SerialPortHomePageState? of(BuildContext context) {
    final serialPortHomePageState = context.findAncestorStateOfType<_SerialPortHomePageState>();
    return serialPortHomePageState;
  }

  @override
  _SerialPortHomePageState createState() => _SerialPortHomePageState();
}

class _SerialPortHomePageState extends State<SerialPortHomePage> {
  // 颜色常量定义
  static const Color vsCodeBackground = Color(0xFF1E1E1E);
  static const Color vsCodeSurface = Color(0xFF252526);
  static const Color vsCodeBlue = Color(0xFF569CD6);
  static const Color vsCodeText = Color(0xFFD4D4D4);
  static const Color vsCodeTextSecondary = Color(0xFF858585);
  static const Color receiveColor = Color(0xFF4EC9B0);
  static const Color sendColor = Color(0xFFCE9178);
  static const Color hexBackgroundColor = Color(0xFF334D4A); // HEX数据背景色

  // 串口相关变量
  SerialPort? _serialPort;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  // 配置参数状态
  String selectedPort = '';
  String selectedBaudRate = '9600';
  String selectedDataBits = '8';
  String selectedStopBits = '1';
  String selectedParity = '无校验';
  bool hexMode = false;
  bool chartMode = false;
  String inputData = "";
  bool isConnected = false;
  bool _isAttemptingConnection = false;
  bool _autoReconnect = false;
  Timer? _reconnectTimer;
  bool showTimestamp = true;

  // 可用串口列表
  List<String> availablePorts = [];

  // 数据接收相关变量
  final List<DataLine> _receivedLines = [];
  final List<EnhancedDataLine> _receivedEnhancedLines = [];
  final ScrollController _receiveScrollController = ScrollController();
  final int _maxDisplayLines = 1000;

  // 数据包重组相关变量
  final StringBuffer _dataBuffer = StringBuffer();
  Timer? _dataTimeoutTimer;
  final int _packetTimeout = 50;
  final int _maxBufferLength = 1024;

  // 动态数据存储
  Map<String, List<FlSpot>> chartData = {};
  List<String> dataKeys = [];
  Map<String, Color> keyColors = {};
  int maxDataPoints = 100;
  int dataIndex = 0;

  final List<Color> availableColors = [
    Color(0xFF569CD6),
    Color(0xFFCE9178),
    Color(0xFF4EC9B0),
    Color(0xFFDCDCAA),
    Color(0xFFC586C0),
    Color(0xFFD16969),
    Color(0xFF9CDCFE),
    Color(0xFFD7BA7D),
  ];

  // WebSocket服务器相关变量
  WebSocketServer? _webSocketServer;
  
  // 公共getter方法
  WebSocketServer? get webSocketServer => _webSocketServer;
  bool _isWebSocketServerRunning = false;
  int _webSocketPort = WebSocketServer.DEFAULT_PORT;

  @override
  void initState() {
    super.initState();
    _refreshPortList();
    _addLine("等待接收数据...", LineType.system);
    _receiveScrollController.addListener(_scrollListener);
    _initWebSocketServer();
  }

  @override
  void dispose() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _reader?.close();
    _serialPort?.close();
    _serialPort?.dispose();
    _dataTimeoutTimer?.cancel();
    _dataBuffer.clear();
    _receiveScrollController.dispose();
    _stopWebSocketServer();
    super.dispose();
  }

  // 初始化WebSocket服务器
  void _initWebSocketServer() async {
    _webSocketServer = WebSocketServer(); // 默认启用认证
    _webSocketServer!.addOnCommandCallback(_handleWebSocketCommandReceived);
    _webSocketServer!.addOnClientConnectCallback(_handleWebSocketClientConnect);
    _webSocketServer!.addOnClientDisconnectCallback(_handleWebSocketClientDisconnect);
    
    try {
      await _webSocketServer!.start(port: _webSocketPort);
      _isWebSocketServerRunning = true;
      _addLine("WebSocket服务器启动在端口: ${_webSocketServer!.port}", LineType.system);
      _addLine("WebSocket认证Token: ${_webSocketServer!.authToken}", LineType.system);
    } catch (e) {
      _addLine("WebSocket服务器启动失败: $e", LineType.system);
    }
  }

  // 停止WebSocket服务器
  void _stopWebSocketServer() {
    if (_webSocketServer != null && _isWebSocketServerRunning) {
      _webSocketServer!.stop();
      _isWebSocketServerRunning = false;
      _addLine("WebSocket服务器已停止", LineType.system);
    }
  }

  // 处理WebSocket接收到的数据（新API - 处理JSON命令）
  void _handleWebSocketCommandReceived(Map<String, dynamic> command) {
    String cmd = command['command'] ?? '';
    Map<String, dynamic> data = command['data'] ?? {};
    
    _addLine("WebSocket命令: $cmd", LineType.system);
    
    // 根据命令类型执行相应操作
    switch (_webSocketServer!.parseCommand(cmd)) {
      case WebSocketCommand.connect:
        _handleWebSocketConnectCommand(data);
        break;
      case WebSocketCommand.disconnect:
        _handleWebSocketDisconnectCommand(data);
        break;
      case WebSocketCommand.listPorts:
        _handleWebSocketListPortsCommand(data);
        break;
      case WebSocketCommand.sendText:
        _handleWebSocketSendTextCommand(data);
        break;
      case WebSocketCommand.sendHex:
        _handleWebSocketSendHexCommand(data);
        break;
      case WebSocketCommand.setConfig:
        _handleWebSocketSetConfigCommand(data);
        break;
      case WebSocketCommand.setHexMode:
        _handleWebSocketSetHexModeCommand(data);
        break;
      case WebSocketCommand.setChartMode:
        _handleWebSocketSetChartModeCommand(data);
        break;
      case WebSocketCommand.unknown:
        // 如果是原始数据，按旧方式处理
        if (cmd == 'raw_data') {
          String message = data['message'] ?? '';
          _handleWebSocketRawDataReceived(message);
        } else {
          _webSocketServer!.sendResponse(WebSocketResponseType.error, {
            'command': cmd,
            'error': '未知命令',
            'code': 4001
          });
        }
        break;
    }
  }

  // 处理连接命令
  void _handleWebSocketConnectCommand(Map<String, dynamic> data) {
    String port = data['port'] ?? '';
    int baudRate = data['baudRate'] ?? 9600;
    int dataBits = data['dataBits'] ?? 8;
    int stopBits = data['stopBits'] ?? 1;
    String parity = data['parity'] ?? 'none';

    if (port.isEmpty) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'connect',
        'error': '串口未指定',
        'code': 4002
      });
      return;
    }

    // 更新UI状态
    setState(() {
      selectedPort = port;
      selectedBaudRate = baudRate.toString();
      selectedDataBits = dataBits.toString();
      selectedStopBits = stopBits.toString();
      selectedParity = _convertParityToString(parity);
    });

    // 尝试连接串口
    _connect(manual: true);

    // 发送响应
    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'connect',
      'success': isConnected,
      'message': isConnected ? '串口连接成功' : '串口连接失败',
      'port': port,
      'baudRate': baudRate
    });

    // 发送端口状态
    _sendPortStatus();
  }

  // 处理断开连接命令
  void _handleWebSocketDisconnectCommand(Map<String, dynamic> data) {
    _disconnect();

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'disconnect',
      'success': true,
      'message': '串口已断开'
    });

    _sendPortStatus();
  }

  // 处理列出端口命令
  void _handleWebSocketListPortsCommand(Map<String, dynamic> data) {
    _refreshPortList();
    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'list_ports',
      'success': true,
      'ports': availablePorts
    });
  }

  // 处理发送文本命令
  void _handleWebSocketSendTextCommand(Map<String, dynamic> data) {
    String message = data['message'] ?? '';
    _sendTextData(message);
  }

  // 处理发送HEX命令
  void _handleWebSocketSendHexCommand(Map<String, dynamic> data) {
    String hex = data['hex'] ?? '';
    _sendHexData(hex);
  }

  // 处理设置配置命令
  void _handleWebSocketSetConfigCommand(Map<String, dynamic> data) {
    if (data.containsKey('baudRate')) {
      setState(() {
        selectedBaudRate = data['baudRate'].toString();
      });
    }
    if (data.containsKey('dataBits')) {
      setState(() {
        selectedDataBits = data['dataBits'].toString();
      });
    }
    if (data.containsKey('stopBits')) {
      setState(() {
        selectedStopBits = data['stopBits'].toString();
      });
    }
    if (data.containsKey('parity')) {
      setState(() {
        selectedParity = _convertParityToString(data['parity']);
      });
    }

    // 如果串口已连接，重新连接以应用新配置
    if (isConnected) {
      _addLine("配置变更，正在重启串口...", LineType.system);
      _handleDisconnect(); // 触发自动重连逻辑
    }

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'set_config',
      'success': true,
      'message': '配置已更新',
      'config': {
        'baudRate': selectedBaudRate,
        'dataBits': selectedDataBits,
        'stopBits': selectedStopBits,
        'parity': selectedParity
      }
    });
  }

  // 处理设置HEX模式命令
  void _handleWebSocketSetHexModeCommand(Map<String, dynamic> data) {
    bool enabled = data['enabled'] ?? false;
    setState(() {
      hexMode = enabled;
    });

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'set_hex_mode',
      'success': true,
      'enabled': enabled,
      'message': 'HEX模式已${enabled ? '启用' : '禁用'}'
    });
  }

  // 处理设置图表模式命令
  void _handleWebSocketSetChartModeCommand(Map<String, dynamic> data) {
    bool enabled = data['enabled'] ?? false;
    setState(() {
      chartMode = enabled;
    });

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'set_chart_mode',
      'success': true,
      'enabled': enabled,
      'message': '图表模式已${enabled ? '启用' : '禁用'}'
    });
  }

  // 处理原始数据（向后兼容）
  void _handleWebSocketRawDataReceived(String data) {
    _addLine("WebSocket接收: $data", LineType.system);
    
    // 如果串口已连接，将WebSocket数据转发到串口
    if (isConnected && _serialPort != null) {
      try {
        Uint8List dataToSend;
        if (hexMode) {
          final cleanedData = data.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
          if (cleanedData.isEmpty) return;
          
          final dataList = <int>[];
          for (int i = 0; i < cleanedData.length; i += 2) {
            final hexByte = cleanedData.substring(i, math.min(i + 2, cleanedData.length));
            dataList.add(int.parse(hexByte, radix: 16));
          }
          dataToSend = Uint8List.fromList(dataList);
        } else {
          dataToSend = Uint8List.fromList(utf8.encode(data + '\r\n'));
        }

        _serialPort!.write(dataToSend);
      } catch (e) {
        _addLine("转发WebSocket数据到串口失败: $e", LineType.system);
      }
    }
  }

  // 发送串口状态
  void _sendPortStatus() {
    _webSocketServer!.sendResponse(WebSocketResponseType.portStatus, {
      'connected': isConnected,
      'port': selectedPort,
      'baudRate': int.tryParse(selectedBaudRate) ?? 9600,
      'hexMode': hexMode,
      'chartMode': chartMode
    });
  }

  // 发送文本数据
  void _sendTextData(String message) {
    if (!isConnected || _serialPort == null) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_text',
        'error': '串口未连接',
        'code': 4003
      });
      return;
    }

    try {
      Uint8List dataToSend = Uint8List.fromList(utf8.encode(message + '\r\n'));
      final bytesWritten = _serialPort!.write(dataToSend);

      if (bytesWritten == dataToSend.length) {
        _addLine(message, LineType.send);
        _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
          'command': 'send_text',
          'success': true,
          'message': '数据发送成功',
          'bytesWritten': bytesWritten
        });
      } else {
        _webSocketServer!.sendResponse(WebSocketResponseType.error, {
          'command': 'send_text',
          'error': '数据发送不完整',
          'code': 4004
        });
      }
    } catch (e) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_text',
        'error': '发送失败: $e',
        'code': 4005
      });
    }
  }

  // 发送HEX数据
  void _sendHexData(String hexString) {
    if (!isConnected || _serialPort == null) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_hex',
        'error': '串口未连接',
        'code': 4003
      });
      return;
    }

    try {
      final cleanedData = hexString.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (cleanedData.isEmpty) {
        _webSocketServer!.sendResponse(WebSocketResponseType.error, {
          'command': 'send_hex',
          'error': '无效的HEX数据',
          'code': 4006
        });
        return;
      }

      final dataList = <int>[];
      for (int i = 0; i < cleanedData.length; i += 2) {
        final hexByte = cleanedData.substring(i, math.min(i + 2, cleanedData.length));
        dataList.add(int.parse(hexByte, radix: 16));
      }
      Uint8List dataToSend = Uint8List.fromList(dataList);

      final bytesWritten = _serialPort!.write(dataToSend);

      if (bytesWritten == dataToSend.length) {
        String displayHex = cleanedData
            .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)} ')
            .trim();
        _addLine('HEX: $displayHex', LineType.send);
        _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
          'command': 'send_hex',
          'success': true,
          'message': 'HEX数据发送成功',
          'bytesWritten': bytesWritten,
          'hex': displayHex
        });
      } else {
        _webSocketServer!.sendResponse(WebSocketResponseType.error, {
          'command': 'send_hex',
          'error': 'HEX数据发送不完整',
          'code': 4004
        });
      }
    } catch (e) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_hex',
        'error': 'HEX发送失败: $e',
        'code': 4005
      });
    }
  }

  // 将奇偶校验值转换为字符串
  String _convertParityToString(dynamic parity) {
    if (parity is int) {
      switch (parity) {
        case 0: return '无校验';
        case 1: return '奇校验';
        case 2: return '偶校验';
        case 3: return '标记';
        case 4: return '空格';
        default: return '无校验';
      }
    } else if (parity is String) {
      return parity;
    } else {
      return '无校验';
    }
  }

  // 处理WebSocket客户端连接
  void _handleWebSocketClientConnect(String clientInfo) {
    _addLine("WebSocket客户端连接: $clientInfo", LineType.system);
  }

  // 处理WebSocket客户端断开连接
  void _handleWebSocketClientDisconnect(String clientInfo) {
    _addLine("WebSocket客户端断开: $clientInfo", LineType.system);
  }

  // 将串口数据发送到WebSocket客户端
  void _sendToWebSocket(String data) {
    if (_webSocketServer != null && _isWebSocketServerRunning) {
      _webSocketServer!.broadcast(data);
    }
  }

  void _scrollListener() {
    if (_receiveScrollController.position.pixels ==
        _receiveScrollController.position.maxScrollExtent) {
      _scrollToBottom();
    }
  }

  void _addLine(String text, LineType type) {
    setState(() {
      _receivedLines.add(
        DataLine(
          text: text,
          type: type,
          timestamp: showTimestamp ? DateTime.now() : null,
        ),
      );

      if (_receivedLines.length > _maxDisplayLines) {
        _receivedLines.removeRange(0, _receivedLines.length - _maxDisplayLines);
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_receiveScrollController.hasClients) {
        // 使用jumpTo而不是animateTo来避免动画导致的视觉问题
        _receiveScrollController.jumpTo(_receiveScrollController.position.maxScrollExtent);
      }
    });
  }

  void _refreshPortList() {
    setState(() {
      availablePorts = SerialPort.availablePorts;
      if (availablePorts.isNotEmpty && selectedPort.isEmpty) {
        selectedPort = availablePorts.first;
      }
    });
  }

  void _connect({bool manual = true}) async {
    if (selectedPort.isEmpty) {
      if (manual) _showMessage('请选择串口');
      return;
    }

    if (manual) _autoReconnect = true;

    try {
      _serialPort = SerialPort(selectedPort);

      if (!_serialPort!.openReadWrite()) {
        _handleDisconnect();
        return;
      }

      // 获取配置对象并设置参数[6](@ref)
      final config = _serialPort!.config;
      config.baudRate = int.parse(selectedBaudRate);
      config.bits = int.parse(selectedDataBits);
      config.parity = _getParityValue(selectedParity);
      config.stopBits = int.parse(selectedStopBits);

      // 将配置应用回串口[6](@ref)
      _serialPort!.config = config;

      _reader = SerialPortReader(_serialPort!, timeout: 10);
      _subscription = _reader!.stream.listen(
        _onDataReceived,
        onError: (e) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );

      setState(() {
        isConnected = true;
        _isAttemptingConnection = false;
      });

      _addLine(
        "串口连接成功 - $selectedBaudRate $selectedDataBits$selectedParity$selectedStopBits",
        LineType.system,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _subscription?.cancel();
    _reader?.close();
    _serialPort?.close();

    if (mounted) {
      setState(() {
        isConnected = false;
        if (_autoReconnect) {
          _isAttemptingConnection = true;
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(Duration(milliseconds: 10), () => _connect(manual: false));
        }
      });
    }
  }

  void _disconnect() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _handleDisconnect();
    _addLine("串口已断开", LineType.system);
  }

  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;

    try {
      // 改进的数据解码逻辑[8](@ref)
      String dataString = _tryMultipleDecodings(data);
      _dataBuffer.write(dataString);

      _dataTimeoutTimer?.cancel();
      _dataTimeoutTimer = Timer(
        Duration(milliseconds: _packetTimeout),
        _processBufferedData,
      );

      if (_dataBuffer.length > _maxBufferLength) {
        _processBufferedData();
      }
    } catch (e) {
      // HEX显示作为备选方案
      String hexString = data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();
      _addLine("HEX: $hexString", LineType.receive);
    }
  }

  // 尝试多种解码方式[8](@ref)
  String _tryMultipleDecodings(Uint8List data) {
    // 首先尝试UTF-8解码（支持中文等多字节字符）
    try {
      String result = utf8.decode(data, allowMalformed: false);
      if (_isValidText(result)) {
        return result;
      }
    } catch (e) {}

    // 尝试UTF-8解码，允许错误字符
    try {
      String result = utf8.decode(data, allowMalformed: true);
      if (_isValidText(result)) {
        return result;
      }
    } catch (e) {}

    // 尝试ASCII解码
    try {
      String result = ascii.decode(data, allowInvalid: false);
      if (_isValidText(result)) {
        return result;
      }
    } catch (e) {}

    // 最后尝试Latin1解码
    try {
      String result = latin1.decode(data, allowInvalid: false);
      if (_isValidText(result)) {
        return result;
      }
    } catch (e) {}

    // 如果所有解码都失败，返回HEX表示
    return data
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join('')
            .toUpperCase() +
        " [HEX]";
  }

  // 验证文本是否包含过多乱码字符
  bool _isValidText(String text) {
    if (text.isEmpty) return false;

    // 计算可打印字符的比例
    int printableCount = 0;
    int chineseCharCount = 0; // 计算中文字符数量
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      // ASCII可打印字符（包括空格、标点、数字、字母）
      if (code >= 32 && code <= 126 || code == 10 || code == 13 || code == 9) {
        printableCount++;
      }
      // 中文字符范围
      else if ((code >= 0x4E00 && code <= 0x9FFF) || // CJK统一汉字
               (code >= 0x3400 && code <= 0x4DBF) || // CJK扩展A
               (code >= 0x20000 && code <= 0x2A6DF) || // CJK扩展B
               (code >= 0x2A700 && code <= 0x2B73F) || // CJK扩展C
               (code >= 0x2B740 && code <= 0x2B81F) || // CJK扩展D
               (code >= 0x2B820 && code <= 0x2CEAF) || // CJK扩展E
               (code >= 0xF900 && code <= 0xFAFF) || // CJK兼容汉字
               (code >= 0x2F800 && code <= 0x2FA1F)) { // CJK兼容汉字补充
        printableCount++;
        chineseCharCount++;
      }
    }

    double printableRatio = printableCount / text.length;
    // 如果中文字符较多，适当降低可打印字符比例要求
    if (chineseCharCount > 0) {
      return printableRatio > 0.5; // 中文文本要求50%以上为可打印字符
    } else {
      return printableRatio > 0.7; // 英文文本要求70%以上为可打印字符
    }
  }

  // 判断字符是否为正常字符（ASCII可打印字符+常见控制字符+中文字符）
  bool _isNormalCharacter(int codePoint) {
    // ASCII可打印字符（包括空格、标点、数字、字母）
    if (codePoint >= 32 && codePoint <= 126) return true;
    
    // 常见控制字符：换行、回车、制表符
    if (codePoint == 10 || codePoint == 13 || codePoint == 9) return true;
    
    // 中文字符范围
    if ((codePoint >= 0x4E00 && codePoint <= 0x9FFF) || // CJK统一汉字
        (codePoint >= 0x3400 && codePoint <= 0x4DBF) || // CJK扩展A
        (codePoint >= 0x20000 && codePoint <= 0x2A6DF) || // CJK扩展B
        (codePoint >= 0x2A700 && codePoint <= 0x2B73F) || // CJK扩展C
        (codePoint >= 0x2B740 && codePoint <= 0x2B81F) || // CJK扩展D
        (codePoint >= 0x2B820 && codePoint <= 0x2CEAF) || // CJK扩展E
        (codePoint >= 0xF900 && codePoint <= 0xFAFF) || // CJK兼容汉字
        (codePoint >= 0x2F800 && codePoint <= 0x2FA1F)) { // CJK兼容汉字补充
      return true;
    }
    
    return false; // 其他字符视为不正常
  }

  // 格式化HEX字符串：添加字符间空格
  String _formatHexWithSpaces(String hexString) {
    if (hexString.isEmpty) return hexString;
    
    StringBuffer formatted = StringBuffer();
    for (int i = 0; i < hexString.length; i += 2) {
      if (i > 0) formatted.write(' ');
      int end = i + 2;
      if (end > hexString.length) end = hexString.length;
      formatted.write(hexString.substring(i, end));
    }
    return formatted.toString();
  }

  // 智能分割文本和HEX数据（简化版）
  List<DataSegment> _splitTextAndHex(String text) {
    List<DataSegment> segments = [];
    
    // 只有在HEX模式下才进行HEX序列识别，文本模式下只处理明显的HEX格式数据
    if (hexMode) {
      // 使用正则表达式查找长HEX序列（≥12个连续HEX字符）
      RegExp hexPattern = RegExp(r'([0-9A-Fa-f]{12,})');
      int lastIndex = 0;
      
      for (RegExpMatch match in hexPattern.allMatches(text)) {
        // 添加匹配前的文本
        if (match.start > lastIndex) {
          String textSegment = text.substring(lastIndex, match.start);
          if (textSegment.trim().isNotEmpty) {
            segments.add(DataSegment(
              content: textSegment,
              type: SegmentType.text,
            ));
          }
        }
        
        // 添加HEX序列（带空格格式化）
        String hexContent = match.group(0)!;
        segments.add(DataSegment(
          content: _formatHexWithSpaces(hexContent),
          type: SegmentType.hex,
        ));
        
        lastIndex = match.end;
      }
      
      // 添加剩余文本
      if (lastIndex < text.length) {
        String remainingText = text.substring(lastIndex);
        if (remainingText.trim().isNotEmpty) {
          segments.add(DataSegment(
            content: remainingText,
            type: SegmentType.text,
          ));
        }
      }
    } else {
      // 文本模式下，只处理明确的HEX格式数据（如 [49 20 28 38 38 32 31 32] 这样的格式）
      // 保持原始文本，不做特殊处理
      segments.add(DataSegment(
        content: text,
        type: SegmentType.text,
      ));
    }
    
    return segments;
  }

  // 处理不正常字符：转换为HEX表示，但不合并
  String _processUnusualCharacters(String text) {
    StringBuffer result = StringBuffer();
    
    for (int i = 0; i < text.length; i++) {
      int codePoint = text.codeUnitAt(i);
      
      if (_isNormalCharacter(codePoint)) {
        // 正常字符，直接添加
        result.write(text[i]);
      } else {
        // 不正常字符，转换为HEX表示，用方括号包围
        String hex = codePoint.toRadixString(16).padLeft(2, '0').toUpperCase();
        result.write('[$hex]');
      }
    }
    
    return result.toString();
  }

  // 将HEX字符串转换为可读文本（如果可能）
  String _convertHexToReadableText(String text) {
    // 检查是否包含HEX格式的数据（如 [6536][5230] 这样的格式）
    RegExp hexBracketPattern = RegExp(r'\[([0-9A-Fa-f]{2,})\]');
    String result = text;
    
    for (Match match in hexBracketPattern.allMatches(text)) {
      String hexContent = match.group(1)!;
      
      // 尝试将HEX内容转换为文本
      if (hexContent.length % 2 == 0) { // 确保是完整的字节序列
        try {
          List<int> bytes = [];
          for (int i = 0; i < hexContent.length; i += 2) {
            String hexByte = hexContent.substring(i, i + 2);
            bytes.add(int.parse(hexByte, radix: 16));
          }
          
          // 尝试将字节转换为UTF-8文本，特别处理中文字符
          String convertedText = utf8.decode(bytes, allowMalformed: true);
          // 保留中文字符和可打印字符，过滤掉真正的乱码字符
          StringBuffer cleanText = StringBuffer();
          for (int j = 0; j < convertedText.length; j++) {
            int codePoint = convertedText.codeUnitAt(j);
            if (_isNormalCharacter(codePoint)) {
              cleanText.write(convertedText[j]);
            }
          }
          String cleanConvertedText = cleanText.toString();
          
          // 如果转换后的文本有意义，则替换原始HEX
          if (cleanConvertedText.isNotEmpty && cleanConvertedText.trim().isNotEmpty) {
            result = result.replaceAll('[${hexContent}]', '[$cleanConvertedText]');
          }
        } catch (e) {
          // 如果转换失败，保留原始格式
          continue;
        }
      }
    }
    
    return result;
  }

  // 添加增强的数据行
  void _addEnhancedLine(List<DataSegment> segments, LineType lineType) {
    setState(() {
      _receivedEnhancedLines.add(EnhancedDataLine(
        segments: segments,
        lineType: lineType,
        timestamp: showTimestamp ? DateTime.now() : null,
      ));
      
      if (_receivedEnhancedLines.length > _maxDisplayLines) {
        _receivedEnhancedLines.removeRange(
          0, 
          _receivedEnhancedLines.length - _maxDisplayLines
        );
      }
    });
    
    _scrollToBottom();
  }

  List<Map<String, double>> _parseBracketedData(String line) {
    List<Map<String, double>> dataList = [];
    try {
      final regex = RegExp(r'\[([^\[\]]+)\]');
      final matches = regex.allMatches(line);

      for (final match in matches) {
        Map<String, double> data = {};
        String content = match.group(1)!;
        List<String> pairs = content.split(',');

        for (String pair in pairs) {
          if (pair.contains(':')) {
            List<String> keyValue = pair.split(':');
            if (keyValue.length >= 2) {
              String key = keyValue[0].trim();
              String value = keyValue[1].trim();
              try {
                double numericValue = double.parse(value);
                data[key] = numericValue;
              } catch (e) {}
            }
          }
        }

        if (data.isNotEmpty) {
          dataList.add(data);
        }
      }
    } catch (e) {}
    return dataList;
  }

  void _processBufferedData() {
    if (_dataBuffer.isEmpty) return;

    String bufferedData = _dataBuffer.toString();
    _dataBuffer.clear();

    List<String> lines = _splitDataLines(bufferedData);

    for (String line in lines) {
      if (line.trim().isEmpty) continue;

      _displayReceivedData(line);

      if (chartMode) {
        _parseChartData(line);
      }
    }
  }

  List<String> _splitDataLines(String data) {
    List<String> lines = [];
    StringBuffer currentLine = StringBuffer();

    for (int i = 0; i < data.length; i++) {
      String char = data[i];
      currentLine.write(char);

      if (char == '\n' || i == data.length - 1) {
        String line = currentLine.toString().trim();
        if (line.isNotEmpty) lines.add(line);
        currentLine.clear();
      }
    }

    return lines;
  }

  void _parseChartData(String line) {
    try {
      List<Map<String, double>> parsedDataList = _parseBracketedData(line);

      for (Map<String, double> parsedData in parsedDataList) {
        if (parsedData.isNotEmpty) {
          for (String key in parsedData.keys) {
            if (!keyColors.containsKey(key)) {
              int colorIndex = keyColors.length % availableColors.length;
              keyColors[key] = availableColors[colorIndex];
              if (!dataKeys.contains(key)) dataKeys.add(key);
            }

            if (!chartData.containsKey(key)) chartData[key] = [];

            double value = parsedData[key]!;
            chartData[key]!.add(FlSpot(dataIndex.toDouble(), value));

            if (chartData[key]!.length > maxDataPoints) {
              chartData[key]!.removeAt(0);
            }
          }
          dataIndex++;
        }
      }

      if (mounted) setState(() {});
    } catch (e) {}
  }

  void _displayReceivedData(String dataString) {
    if (dataString.isEmpty) return;
    
    // 只有在HEX模式下才进行特殊处理，否则直接显示原始数据
    if (hexMode) {
      // 先处理不正常字符
      String processedString = _processUnusualCharacters(dataString);
      
      // 尝试将HEX格式转换为可读文本
      String convertedString = _convertHexToReadableText(processedString);
      
      // 使用智能分割算法处理混合数据
      List<DataSegment> segments = _splitTextAndHex(convertedString);
      _addEnhancedLine(segments, LineType.receive);
      _sendToWebSocket(convertedString); // 将数据发送到WebSocket客户端
    } else {
      // 非HEX模式下，直接处理原始数据，保留中文字符
      List<DataSegment> segments = _splitTextAndHex(dataString);
      _addEnhancedLine(segments, LineType.receive);
      _sendToWebSocket(dataString); // 将数据发送到WebSocket客户端
    }
  }

  void _sendData() {
    if (!isConnected || _serialPort == null) {
      _showMessage('请先连接串口');
      return;
    }

    if (inputData.isEmpty) return;

    try {
      Uint8List dataToSend;

      if (hexMode) {
        final cleanedData = inputData.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
        if (cleanedData.isEmpty) {
          _showMessage('请输入有效的HEX数据');
          return;
        }

        final dataList = <int>[];
        for (int i = 0; i < cleanedData.length; i += 2) {
          final hexByte = cleanedData.substring(
            i,
            math.min(i + 2, cleanedData.length),
          );
          dataList.add(int.parse(hexByte, radix: 16));
        }
        dataToSend = Uint8List.fromList(dataList);
      } else {
        dataToSend = Uint8List.fromList(utf8.encode(inputData + '\r\n'));
      }

      final bytesWritten = _serialPort!.write(dataToSend);

      if (bytesWritten == dataToSend.length) {
        // 发送数据时，同时添加到增强数据行列表以确保一致的显示
        List<DataSegment> segments = _splitTextAndHex(inputData);
        _addEnhancedLine(segments, LineType.send);
        _sendToWebSocket(inputData); // 将发送的数据也广播到WebSocket客户端
        setState(() {
          inputData = '';
        });
      } else {
        _showMessage('数据发送不完整');
      }
    } catch (e) {
      _showMessage('发送失败: $e');
    }
  }

  void _copyReceivedData() {
    if (_receivedEnhancedLines.isNotEmpty) {
      // 使用增强数据行进行复制
      String textToCopy = _receivedEnhancedLines
          .map((line) => line.toString())
          .join('\n');
      Clipboard.setData(ClipboardData(text: textToCopy));
      _showMessage('内容已复制到剪贴板 (${_receivedEnhancedLines.length} 行)');
    } else if (_receivedLines.isNotEmpty) {
      // 使用普通数据行进行复制
      String textToCopy = _receivedLines
          .map((line) => line.toString())
          .join('\n');
      Clipboard.setData(ClipboardData(text: textToCopy));
      _showMessage('内容已复制到剪贴板 (${_receivedLines.length} 行)');
    } else {
      _showMessage('没有可复制的内容');
    }
  }

  void _clearReceivedData() {
    setState(() {
      _receivedLines.clear();
      _receivedEnhancedLines.clear();
      _addLine("清空记录", LineType.system);
      chartData.clear();
      dataKeys.clear();
      keyColors.clear();
      dataIndex = 0;
    });
  }

  int _getParityValue(String parity) {
    switch (parity) {
      case '奇校验':
        return SerialPortParity.odd;
      case '偶校验':
        return SerialPortParity.even;
      case '标记':
        return SerialPortParity.mark;
      case '空格':
        return SerialPortParity.space;
      default:
        return SerialPortParity.none;
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text('动态串口图表工具', style: TextStyle(color: vsCodeBlue)),
        backgroundColor: vsCodeBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: vsCodeBlue),
            onPressed: _refreshPortList,
            tooltip: '刷新串口列表',
          ),
          Container(
            margin: EdgeInsets.all(8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isConnected 
                  ? Colors.green 
                  : (_autoReconnect ? Colors.orange : Colors.red),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isConnected ? '已连接' : (_autoReconnect ? '重连中...' : '未连接'),
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Container(
        color: vsCodeBackground,
        padding: EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  _buildDataDisplayArea(),
                  SizedBox(height: 20),
                  _buildInputControlArea(),
                  SizedBox(height: 20),
                  Expanded(child: _buildChartArea()),
                ],
              ),
            ),
            SizedBox(width: 20),
            _buildConfigPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildDataDisplayArea() {
    return Container(
      height: 250,
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
                Icon(Icons.input, color: vsCodeBlue, size: 16),
                SizedBox(width: 8),
                Text(
                  '接收的数据 (${_receivedLines.length} 行)',
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
                    Text(
                      '接收',
                      style: TextStyle(color: vsCodeText, fontSize: 10),
                    ),
                    SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      color: sendColor,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text(
                      '发送',
                      style: TextStyle(color: vsCodeText, fontSize: 10),
                    ),
                    SizedBox(width: 16),
                  ],
                ),
                TextButton(
                  onPressed: _copyReceivedData,
                  child: Text(
                    '复制',
                    style: TextStyle(color: vsCodeBlue, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _clearReceivedData,
                  child: Text(
                    '清空',
                    style: TextStyle(color: vsCodeBlue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _receiveScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _receiveScrollController,
                itemCount: _receivedEnhancedLines.isNotEmpty ? _receivedEnhancedLines.length : _receivedLines.length,
                itemBuilder: (context, index) {
                  if (_receivedEnhancedLines.isNotEmpty) {
                    return _buildEnhancedDataLine(_receivedEnhancedLines[index], index);
                  } else {
                    return _buildDataLine(_receivedLines[index], index);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLine(DataLine dataLine, int index) {
    Color lineColor = vsCodeText;

    switch (dataLine.type) {
      case LineType.send:
        lineColor = sendColor;
        break;
      case LineType.receive:
        lineColor = receiveColor;
        break;
      case LineType.system:
        lineColor = vsCodeTextSecondary;
        break;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SelectableText(
        dataLine.toString(),
        style: TextStyle(color: lineColor, fontSize: 14),
        selectionControls: MaterialTextSelectionControls(), // 启用文本选择控件
      ),
    );
  }

  Widget _buildEnhancedDataLine(EnhancedDataLine dataLine, int index) {
    Color textColor = vsCodeText;
    
    switch (dataLine.lineType) {
      case LineType.send:
        textColor = sendColor;
        break;
      case LineType.receive:
        textColor = receiveColor;
        break;
      case LineType.system:
        textColor = vsCodeTextSecondary;
        break;
    }
    
    // 构建时间戳前缀
    String timePrefix = '';
    if (dataLine.timestamp != null && showTimestamp) {
      String timeStr = dataLine.timestamp!.toString().substring(11, 19);
      switch (dataLine.lineType) {
        case LineType.send:
          timePrefix = '$timeStr 发送: ';
          break;
        case LineType.receive:
          timePrefix = '$timeStr 接收: ';
          break;
        case LineType.system:
          timePrefix = '$timeStr ';
          break;
      }
    }
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SelectableText.rich(
        TextSpan(
          children: [
            // 时间戳前缀
            TextSpan(
              text: timePrefix,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
            // 数据片段
            ...dataLine.segments.map((segment) {
              if (segment.type == SegmentType.text) {
                return TextSpan(
                  text: segment.content,
                  style: TextStyle(color: textColor, fontSize: 14),
                );
              } else {
                // HEX数据：添加空格分隔并使用背景色
                return TextSpan(
                  text: ' ${segment.content} ',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    backgroundColor: hexBackgroundColor,
                  ),
                );
              }
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputControlArea() {
    final ScrollController _inputScrollController = ScrollController();

    return Container(
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Container(
                constraints: BoxConstraints(minHeight: 50, maxHeight: 120),
                decoration: BoxDecoration(
                  border: Border.all(color: vsCodeBlue, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Scrollbar(
                  controller: _inputScrollController,
                  thumbVisibility: true,
                  child: TextField(
                    onChanged: (value) => inputData = value,
                    controller: TextEditingController(text: inputData),
                    style: TextStyle(color: vsCodeText),
                    maxLines: null,
                    scrollController: _inputScrollController,
                    decoration: InputDecoration(
                      hintText: hexMode
                          ? '输入HEX数据（如: 48 65 6C 6C 6F）'
                          : '输入要发送的文本',
                      hintStyle: TextStyle(color: vsCodeTextSecondary),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Container(
              constraints: BoxConstraints(minWidth: 100, minHeight: 50),
              child: ElevatedButton(
                onPressed: _sendData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: vsCodeBackground,
                  foregroundColor: vsCodeBlue,
                  side: BorderSide(
                    color: vsCodeBlue.withOpacity(0.7),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send, size: 18),
                    SizedBox(width: 6),
                    Text('发信'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartArea() {
    return SizedBox(
      height: 200,
      child: Container(
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
                  Icon(Icons.show_chart, color: vsCodeBlue, size: 16),
                  SizedBox(width: 8),
                  Text(
                    '动态数据图表',
                    style: TextStyle(
                      color: vsCodeBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: dataKeys.isEmpty
                        ? Container()
                        : Text(
                            '数据键: ${dataKeys.join(', ')}',
                            style: TextStyle(color: vsCodeText, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: chartMode && dataKeys.isNotEmpty
                  ? _buildDynamicChart()
                  : Center(
                      child: Text(
                        chartMode
                            ? '等待数据...\n格式示例: [data:123,BatVoltage:13.24,Demo:2]'
                            : '图表显示区域\n点击"开启图表"启用可视化',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: vsCodeTextSecondary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicChart() {
    bool hasValidData = false;
    for (String key in dataKeys) {
      if (chartData.containsKey(key) && chartData[key]!.isNotEmpty) {
        hasValidData = true;
        break;
      }
    }

    if (!hasValidData) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('等待数据...', style: TextStyle(color: vsCodeTextSecondary)),
            SizedBox(height: 8),
            Text(
              '最新接收: ${_receivedLines.isNotEmpty ? _receivedLines.last.text : '无数据'}',
              style: TextStyle(color: vsCodeTextSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    int maxPoints = 0;

    for (String key in dataKeys) {
      List<FlSpot> points = chartData[key]!;
      if (points.isNotEmpty) {
        maxPoints = math.max(maxPoints, points.length);
        for (FlSpot point in points) {
          if (point.y < minY) minY = point.y;
          if (point.y > maxY) maxY = point.y;
        }
      }
    }

    if (minY == double.infinity) minY = 0;
    if (maxY == double.negativeInfinity) maxY = 1;
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    double yMargin = (maxY - minY) * 0.1;
    minY -= yMargin;
    maxY += yMargin;

    List<LineChartBarData> lineBars = dataKeys.map((key) {
      return LineChartBarData(
        spots: chartData[key]!,
        isCurved: true,
        color: keyColors[key]!,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: keyColors[key]!.withOpacity(0.1),
        ),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LineChart(
        LineChartData(
          lineBarsData: lineBars,
          minX: math.max(0, dataIndex - maxDataPoints).toDouble(),
          maxX: dataIndex.toDouble(),
          minY: minY,
          maxY: maxY,
          titlesData: FlTitlesData(
            show: true,
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: math.max(1, (maxDataPoints / 5)),
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      value.toInt().toString(),
                      style: TextStyle(color: vsCodeText, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: (maxY - minY) / 5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toStringAsFixed(2),
                    style: TextStyle(color: vsCodeText, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
            verticalInterval: math.max(1, (maxDataPoints / 10)),
            horizontalInterval: (maxY - minY) / 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: vsCodeTextSecondary.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: vsCodeTextSecondary.withOpacity(0.1),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: vsCodeBlue.withOpacity(0.3), width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        border: Border.all(color: vsCodeBlue.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildConnectionButton(),
            SizedBox(height: 20),
            _buildConfigItem('串口号', selectedPort, availablePorts),
            SizedBox(height: 12),
            _buildConfigItem('波特率', selectedBaudRate, [
              '4800',
              '9600',
              '19200',
              '38400',
              '57600',
              '115200',
            ]),
            SizedBox(height: 12),
            _buildConfigItem('数据位', selectedDataBits, ['5', '6', '7', '8']),
            SizedBox(height: 12),
            _buildConfigItem('停止位', selectedStopBits, ['1', '1.5', '2']),
            SizedBox(height: 12),
            _buildConfigItem('校验码', selectedParity, [
              '无校验',
              '奇校验',
              '偶校验',
              '标记',
              '空格',
            ]),
            SizedBox(height: 12),
            _buildHexModeToggle(),
            SizedBox(height: 12),
            _buildTimestampToggle(),
            SizedBox(height: 20),
            _buildChartToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionButton() {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isConnected ? _disconnect : _connect,
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? Colors.red : Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isConnected ? Icons.close : Icons.usb, size: 16),
            SizedBox(width: 6),
            Text(isConnected ? '断开连接' : '连接串口'),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(String label, String value, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: vsCodeBlue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: vsCodeBlue, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: vsCodeSurface,
              style: TextStyle(color: vsCodeText, fontSize: 12),
              icon: Icon(Icons.arrow_drop_down, color: vsCodeBlue),
              items: options.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  if (label == '串口号') selectedPort = newValue!;
                  if (label == '波特率') selectedBaudRate = newValue!;
                  if (label == '数据位') selectedDataBits = newValue!;
                  if (label == '停止位') selectedStopBits = newValue!;
                  if (label == '校验码') selectedParity = newValue!;
                });
                if (isConnected) {
                  _addLine("配置变更，正在重启串口...", LineType.system);
                  _handleDisconnect(); // 触发自动重连逻辑
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHexModeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HEX模式',
          style: TextStyle(
            color: vsCodeBlue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            hexMode ? 'HEX模式' : '文本模式',
            style: TextStyle(color: vsCodeText, fontSize: 12),
          ),
          value: hexMode,
          activeColor: vsCodeBlue,
          onChanged: (value) => setState(() => hexMode = value),
        ),
      ],
    );
  }

  Widget _buildTimestampToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '时间戳显示',
          style: TextStyle(
            color: vsCodeBlue,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            showTimestamp ? '显示时间戳' : '隐藏时间戳',
            style: TextStyle(color: vsCodeText, fontSize: 12),
          ),
          value: showTimestamp,
          activeColor: vsCodeBlue,
          onChanged: (value) => setState(() => showTimestamp = value),
        ),
      ],
    );
  }

  Widget _buildChartToggle() {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            chartMode = !chartMode;
            if (!chartMode) {
              chartData.clear();
              dataKeys.clear();
              keyColors.clear();
              dataIndex = 0;
            }
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: vsCodeSurface,
          foregroundColor: vsCodeBlue,
          side: BorderSide(color: vsCodeBlue, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(chartMode ? Icons.table_chart : Icons.show_chart, size: 16),
            SizedBox(width: 6),
            Text(chartMode ? '关闭图表' : '开启图表'),
          ],
        ),
      ),
    );
  }
}

// 数据片段类型定义
enum SegmentType { text, hex }

// 数据片段类
class DataSegment {
  final String content;
  final SegmentType type;
  
  DataSegment({required this.content, required this.type});
}

// 数据行类型定义
enum LineType { send, receive, system }

// 增强的数据行类
class EnhancedDataLine {
  final List<DataSegment> segments;
  final LineType lineType;
  final DateTime? timestamp;
  
  EnhancedDataLine({
    required this.segments,
    required this.lineType,
    this.timestamp,
  });
  
  @override
  String toString() {
    String content = segments.map((segment) => segment.content).join();
    if (timestamp != null) {
      String timeStr = timestamp!.toString().substring(11, 19);
      switch (lineType) {
        case LineType.send:
          return '$timeStr 发送: $content';
        case LineType.receive:
          return '$timeStr 接收: $content';
        case LineType.system:
          return '$timeStr $content';
      }
    } else {
      return content;
    }
  }
}

// 旧数据行类（保持向后兼容）
class DataLine {
  final String text;
  final LineType type;
  final DateTime? timestamp;

  DataLine({required this.text, required this.type, this.timestamp});

  @override
  String toString() {
    if (timestamp != null) {
      String timeStr = timestamp!.toString().substring(11, 19);
      switch (type) {
        case LineType.send:
          return '$timeStr 发送: $text';
        case LineType.receive:
          return '$timeStr 接收: $text';
        case LineType.system:
          return '$timeStr $text';
      }
    } else {
      return text;
    }
  }
}

// ==========================================
// 固件烧录页面 (基于 esptool v5.2.0)
// ==========================================
class FirmwareFlashPage extends StatefulWidget {
  @override
  _FirmwareFlashPageState createState() => _FirmwareFlashPageState();
}

class _FirmwareFlashPageState extends State<FirmwareFlashPage> {
  // 主题颜色（与主界面保持一致）
  static const Color vsCodeBackground = Color(0xFF1E1E1E);
  static const Color vsCodeSurface = Color(0xFF252526);
  static const Color vsCodeBlue = Color(0xFF569CD6);
  static const Color vsCodeText = Color(0xFFD4D4D4);
  static const Color vsCodeTextSecondary = Color(0xFF858585);
  static const Color successColor = Color(0xFF4EC9B0);
  static const Color errorColor = Color(0xFFF48771);

  // 默认配置（直接填入你需要烧录的路径和参数）
  String _esptoolPath = './esptool';
  String _chip = 'esp32c3';
  String _port = '';
  bool _encrypt = true;
  
  List<String> _availablePorts =[];

  final TextEditingController _bootloaderPathCtrl = TextEditingController(text: '');
  final TextEditingController _partitionPathCtrl = TextEditingController(text: '');
  final TextEditingController _appPathCtrl = TextEditingController(text: '');

  final TextEditingController _bootloaderAddrCtrl = TextEditingController(text: '0x0');
  final TextEditingController _partitionAddrCtrl = TextEditingController(text: '0xC000');
  final TextEditingController _appAddrCtrl = TextEditingController(text: '0x20000');

  final List<String> _outputLog =[];
  final ScrollController _scrollController = ScrollController();
  
  bool _isFlashing = false;
  Process? _flashProcess;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
    _appendLog('等待就绪...');
    _appendLog('默认适配: esptool v5.2.0 命令行工具');
  }

  @override
  void dispose() {
    _flashProcess?.kill();
    _scrollController.dispose();
    _bootloaderPathCtrl.dispose();
    _partitionPathCtrl.dispose();
    _appPathCtrl.dispose();
    _bootloaderAddrCtrl.dispose();
    _partitionAddrCtrl.dispose();
    _appAddrCtrl.dispose();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
      if (_availablePorts.isNotEmpty && (_port.isEmpty || !_availablePorts.contains(_port))) {
        _port = _availablePorts.first;
      }
    });
  }

  void _appendLog(String text, {bool isError = false}) {
    setState(() {
      final prefix = isError ? '[ERROR] ' : '';
      _outputLog.add('$prefix$text');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ==================== 修改：附带校验与自动下载逻辑的烧录进程 ====================
  Future<void> _startFlashing() async {
    setState(() {
      _isFlashing = true;
      _outputLog.clear();
    });

    // 1. 检查 esptool 二进制文件是否存在，若缺失则触发下载
    File esptoolFile = File(_esptoolPath);
    if (!await esptoolFile.exists()) {
      _appendLog('未能在[$_esptoolPath] 找到 esptool 执行文件。', isError: true);
      _appendLog('正在尝试自动下载并配置对应的 esptool 工具链...');
      
      bool success = await _downloadEsptool();
      if (!success) {
        _appendLog('工具链自动配置失败，请检查网络或手动下载并指定路径。', isError: true);
        setState(() {
          _isFlashing = false;
        });
        return;
      }
    } else {
      // 若存在则确保 Linux 环境下具备可执行权限
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod',['+x', _esptoolPath]);
      }
    }

    if (_port.isEmpty) {
      _appendLog('错误: 请先选择串口 (例如: /dev/ttyACM0)', isError: true);
      setState(() {
        _isFlashing = false;
      });
      return;
    }

    // 2. 拼装命令参数
    List<String> args = [
      '--chip', _chip,
      '--port', _port,
      'write-flash'
    ];
    
    if (_encrypt) {
      args.add('--encrypt');
    }
    
    if (_bootloaderPathCtrl.text.isNotEmpty) {
      args.addAll([_bootloaderAddrCtrl.text, _bootloaderPathCtrl.text]);
    }
    if (_partitionPathCtrl.text.isNotEmpty) {
      args.addAll([_partitionAddrCtrl.text, _partitionPathCtrl.text]);
    }
    if (_appPathCtrl.text.isNotEmpty) {
      args.addAll([_appAddrCtrl.text, _appPathCtrl.text]);
    }

    _appendLog('执行命令: $_esptoolPath ${args.join(' ')}');
    _appendLog('----------------------------------------------------');

    try {
      _flashProcess = await Process.start(_esptoolPath, args);

      _flashProcess!.stdout.transform(utf8.decoder).listen((data) {
        final lines = data.split(RegExp(r'[\r\n]+'));
        for (var line in lines) {
          if (line.trim().isNotEmpty) _appendLog(line.trim());
        }
      });

      _flashProcess!.stderr.transform(utf8.decoder).listen((data) {
        final lines = data.split(RegExp(r'[\r\n]+'));
        for (var line in lines) {
          if (line.trim().isNotEmpty) _appendLog(line.trim(), isError: true);
        }
      });

      int exitCode = await _flashProcess!.exitCode;
      _appendLog('----------------------------------------------------');
      if (exitCode == 0) {
        _appendLog('烧录成功完成！', isError: false);
      } else {
        _appendLog('烧录失败，退出代码: $exitCode', isError: true);
      }
    } catch (e) {
      _appendLog('启动进程失败: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isFlashing = false;
          _flashProcess = null;
        });
      }
    }
  }

  // ==================== 新增：自动下载和配置工具链（跨平台支持） ====================
  Future<bool> _downloadEsptool() async {
    String version = 'v5.2.0';
    String fileName = '';
    String url = '';
    String saveDir = '${Directory.current.path}/tools';

    // 根据操作系统选择对应的文件
    if (Platform.isWindows) {
      fileName = 'esptool-$version-windows-amd64.zip';
      _appendLog('检测到 Windows 系统，下载 Windows 版本...');
    } else if (Platform.isLinux) {
      fileName = 'esptool-$version-linux-amd64.tar.gz';
      _appendLog('检测到 Linux 系统，下载 Linux 版本...');
    } else if (Platform.isMacOS) {
      fileName = 'esptool-$version-macos-universal.tar.gz';
      _appendLog('检测到 macOS 系统，下载 macOS 版本...');
    } else {
      _appendLog('不支持的操作系统，请手动下载 esptool', isError: true);
      return false;
    }

    url = 'https://github.com/espressif/esptool/releases/download/$version/$fileName';

    try {
      Directory(saveDir).createSync(recursive: true);
      String savePath = '$saveDir/$fileName';

      _appendLog('开始下载 esptool $version ...');
      _appendLog('目标路径: $savePath');

      var httpClient = HttpClient();
      var request = await httpClient.getUrl(Uri.parse(url));
      var response = await request.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        var file = File(savePath);
        var sink = file.openWrite();

        int downloaded = 0;
        int contentLength = response.contentLength;
        int lastReportedProgress = -1;

        await response.listen((List<int> chunk) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (contentLength > 0) {
            int progress = (downloaded * 100 / contentLength).round();
            // 每隔 10% 汇报一次进度
            if (progress % 10 == 0 && progress != lastReportedProgress) {
              _appendLog('下载进度: $progress%');
              lastReportedProgress = progress;
            }
          }
        }).asFuture();

        await sink.close();
        _appendLog('下载完成，正在解压...');

        // 根据操作系统使用不同的解压方式
        bool extractSuccess = false;
        if (Platform.isWindows) {
          // Windows 使用 zip 解压
          try {
            // 尝试使用 PowerShell 解压
            var result = await Process.run('powershell', [
              '-Command',
              'Expand-Archive -Path "$savePath" -DestinationPath "$saveDir" -Force'
            ]);
            if (result.exitCode == 0) {
              extractSuccess = true;
            } else {
              // 如果 PowerShell 失败，尝试使用内置的 zip 库
              _appendLog('PowerShell 解压失败，尝试备用方案...');
              // 这里可以添加备用解压逻辑
            }
          } catch (e) {
            _appendLog('Windows 解压失败: $e', isError: true);
          }
        } else {
          // Linux/macOS 使用 tar 解压
          var result = await Process.run('tar', ['-xzf', savePath, '-C', saveDir]);
          if (result.exitCode == 0) {
            extractSuccess = true;
          } else {
            _appendLog('解压失败: ${result.stderr}', isError: true);
          }
        }

        if (!extractSuccess) {
          return false;
        }

        await file.delete(); // 删除临时压缩包

        // 查找解压后的二进制文件
        String extractedBinaryPath = '';
        
        // 尝试多个可能的路径
        List<String> possiblePaths = [
          '$saveDir/esptool-$version-windows-amd64/esptool.exe',
          '$saveDir/esptool-$version-linux-amd64/esptool',
          '$saveDir/esptool-$version-macos-universal/esptool',
          '$saveDir/esptool.exe',
          '$saveDir/esptool',
        ];

        for (String path in possiblePaths) {
          if (await File(path).exists()) {
            extractedBinaryPath = path;
            break;
          }
        }

        if (extractedBinaryPath.isEmpty) {
          _appendLog('解压后未能在预期路径找到 esptool 可执行文件', isError: true);
          return false;
        }

        // 非 Windows 系统赋予可执行权限
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', extractedBinaryPath]);
        }

        // 更新 UI 上的路径指向
        setState(() {
          _esptoolPath = extractedBinaryPath;
        });

        _appendLog('esptool 工具链准备完毕！路径: $_esptoolPath');
        return true;
      } else {
        _appendLog('下载失败，HTTP 状态码: ${response.statusCode}', isError: true);
        return false;
      }
    } catch (e) {
      _appendLog('下载或配置异常: $e', isError: true);
      return false;
    }
  }

  void _stopFlashing() {
    if (_flashProcess != null) {
      _flashProcess!.kill();
      _appendLog('操作已被用户手动中止。', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ESP32 固件烧录面板', style: TextStyle(color: vsCodeBlue)),
        backgroundColor: vsCodeBackground,
        elevation: 0,
      ),
      body: Container(
        color: vsCodeBackground,
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 配置区域 ==========
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: vsCodeBlue.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField('esptool 路径', (val) => _esptoolPath = val, _esptoolPath),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildTextField('芯片 (--chip)', (val) => _chip = val, _chip),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('串口号 (--port)', style: TextStyle(color: vsCodeBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                            SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 36,
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: vsCodeTextSecondary.withOpacity(0.5)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _port.isNotEmpty && _availablePorts.contains(_port) ? _port : null,
                                        isExpanded: true,
                                        dropdownColor: vsCodeSurface,
                                        style: TextStyle(color: vsCodeText, fontSize: 13),
                                        items: _availablePorts.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                        onChanged: (val) {
                                          setState(() => _port = val!);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.refresh, color: vsCodeBlue, size: 20),
                                  onPressed: _refreshPorts,
                                  tooltip: '刷新系统设备列表',
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('附加选项', style: TextStyle(color: vsCodeBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Checkbox(
                                value: _encrypt,
                                activeColor: vsCodeBlue,
                                onChanged: (val) => setState(() => _encrypt = val!),
                              ),
                              Text('加密 (--encrypt)', style: TextStyle(color: vsCodeText, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Divider(color: vsCodeTextSecondary.withOpacity(0.3)),
                  SizedBox(height: 8),
                  _buildFileRow('Bootloader', _bootloaderAddrCtrl, _bootloaderPathCtrl),
                  SizedBox(height: 12),
                  _buildFileRow('Partition Table', _partitionAddrCtrl, _partitionPathCtrl),
                  SizedBox(height: 12),
                  _buildFileRow('ESP-NOW App', _appAddrCtrl, _appPathCtrl),
                ],
              ),
            ),
            SizedBox(height: 16),
            // ========== 按钮区域 ==========
            Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(_isFlashing ? Icons.stop : Icons.flash_on, size: 18),
                  label: Text(_isFlashing ? '终止烧录' : '执行烧录 (Write Flash)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFlashing ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: _isFlashing ? _stopFlashing : _startFlashing,
                ),
                SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: Icon(Icons.delete_outline, size: 18),
                  label: Text('清空终端'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vsCodeSurface,
                    foregroundColor: vsCodeText,
                    side: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5)),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {
                    setState(() {
                      _outputLog.clear();
                    });
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            // ========== 日志控制台 ==========
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: vsCodeBlue, width: 2),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black, // 控制台深色背景
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
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
                          Icon(Icons.terminal, color: vsCodeBlue, size: 16),
                          SizedBox(width: 8),
                          Text(
                            '标准输出终端 (esptool process)',
                            style: TextStyle(color: vsCodeBlue, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.all(12),
                          itemCount: _outputLog.length,
                          itemBuilder: (context, index) {
                            String log = _outputLog[index];
                            Color textColor = vsCodeText;
                            
                            // 简单基于正则上色
                            if (log.startsWith('[ERROR]') || log.contains('failed') || log.contains('Error')) {
                              textColor = errorColor;
                            } else if (log.contains('成功') || log.contains('Done') || log.contains('Leaving...') || log.contains('Wrote')) {
                              textColor = successColor;
                            } else if (log.contains('esptool.py v5.2')) {
                              textColor = vsCodeBlue;
                            }
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: SelectableText(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: textColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 内部小组件
  Widget _buildTextField(String label, Function(String) onChanged, String initValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: vsCodeBlue, fontSize: 12, fontWeight: FontWeight.bold)),
        SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextFormField(
            // 绑定 ValueKey，确保当下载完成后外部变量更新时组件会重绘
            key: ValueKey(initValue),
            initialValue: initValue,
            onChanged: onChanged,
            style: TextStyle(color: vsCodeText, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeBlue)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileRow(String label, TextEditingController addrCtrl, TextEditingController pathCtrl) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: TextStyle(color: vsCodeText, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          width: 100,
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: addrCtrl,
              style: TextStyle(color: successColor, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                labelText: '起始地址',
                labelStyle: TextStyle(color: vsCodeTextSecondary, fontSize: 12),
                border: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeBlue)),
              ),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: pathCtrl,
              style: TextStyle(color: vsCodeText, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                labelText: '文件绝对路径 (.bin)',
                labelStyle: TextStyle(color: vsCodeTextSecondary, fontSize: 12),
                border: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeBlue)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}