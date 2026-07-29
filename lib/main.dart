import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_theme.dart';
import 'websocket_server.dart';
import 'websocket_control_page.dart';
import 'ssh_terminal_page.dart';

void main() {
  // 在运行应用之前，确保插件系统已初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  print('启动通信工具应用 - 使用Rust USB捕获实现');
  
  runApp(CommunicationToolApp());
}

class CommunicationToolApp extends StatefulWidget {
  @override
  _CommunicationToolAppState createState() => _CommunicationToolAppState();
}

class _CommunicationToolAppState extends State<CommunicationToolApp> {
  bool _isDarkMode = true;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors(isDarkMode: _isDarkMode, child: SizedBox());
    return AppColors(
      isDarkMode: _isDarkMode,
      child: MaterialApp(
        title: '通信工具',
        debugShowCheckedModeBanner: false,
        theme: colors.themeData,
        home: HomePage(onToggleTheme: _toggleTheme),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback onToggleTheme;

  const HomePage({Key? key, required this.onToggleTheme}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showSettingsDialog(BuildContext context) {
    final colors = AppColors.of(context);
    showDialog(
      context: context,
      builder: (context) {
        bool isDarkMode = colors.isDarkMode;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colors.surface,
              title: Row(
                children: [
                  Icon(Icons.settings, color: colors.primary),
                  SizedBox(width: 8),
                  Text('设置', style: TextStyle(color: colors.text)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                      isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: colors.primary,
                    ),
                    title: Text('主题模式', style: TextStyle(color: colors.text)),
                    subtitle: Text(
                      isDarkMode ? '深色模式' : '白昼模式',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    trailing: Switch(
                      value: isDarkMode,
                      activeColor: colors.primary,
                      onChanged: (value) {
                        setDialogState(() {
                          isDarkMode = value;
                        });
                      },
                    ),
                    onTap: () {
                      setDialogState(() {
                        isDarkMode = !isDarkMode;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (isDarkMode != colors.isDarkMode) {
                      widget.onToggleTheme();
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text('确定', style: TextStyle(color: colors.primary)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('取消', style: TextStyle(color: colors.textSecondary)),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: colors.navRailBackground,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: NavigationRailLabelType.selected,
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.settings_input_component, color: colors.navigationRailColor(_selectedIndex, 0)),
                selectedIcon: Icon(Icons.settings_input_component, color: colors.primary),
                label: Text('串口通信', style: TextStyle(color: colors.navigationRailColor(_selectedIndex, 0))),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.network_wifi, color: colors.navigationRailColor(_selectedIndex, 1)),
                selectedIcon: Icon(Icons.network_wifi, color: colors.primary),
                label: Text('WebSocket控制', style: TextStyle(color: colors.navigationRailColor(_selectedIndex, 1))),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.terminal, color: colors.navigationRailColor(_selectedIndex, 2)),
                selectedIcon: Icon(Icons.terminal, color: colors.primary),
                label: Text('SSH终端', style: TextStyle(color: colors.navigationRailColor(_selectedIndex, 2))),
              ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Stack(
              children: [
                IndexedStack(
                  index: _selectedIndex,
                  children: [
                    SerialPortHomePage(),
                    WebSocketControlPage(),
                    SshTerminalPage(),
                  ],
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: FloatingActionButton.small(
                    onPressed: () => _showSettingsDialog(context),
                    tooltip: '设置',
                    child: Icon(Icons.settings),
                  ),
                ),
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
  AppColors get _colors => AppColors.of(context);

  // 多串口管理相关变量
  int _nextPortIndex = 0;
  Map<String, PortConnection> _portConnections = {};
  
  int get _connectedPortCount => _portConnections.values.where((p) => p.isConnected).length;

  // 全局配置参数（应用于新连接的端口）
  String globalBaudRate = '9600';
  String globalDataBits = '8';
  String globalStopBits = '1';
  String globalParity = '无校验';
  bool hexMode = false;
  bool chartMode = false;
  String inputData = "";
  String selectedSendPort = '';  // 发送数据的目标串口
  bool showTimestamp = true;
  bool _monitorAllPorts = true;
  String _selectedMonitorPort = '';
  ConnectionMode _connectionMode = ConnectionMode.all;
  Set<String> _groupPorts = {};
  String _singleConnectPort = '';

  // 可用串口列表
  List<String> availablePorts = [];

  // 数据接收相关变量
  final List<DataLine> _receivedLines = [];
  final List<EnhancedDataLine> _receivedEnhancedLines = [];
  final ScrollController _receiveScrollController = ScrollController();
  final int _maxDisplayLines = 1000;

  // 数据包重组相关参数
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
    _addLine("多串口监控就绪，点击\"连接所有\"或单独连接串口", LineType.system);
    _receiveScrollController.addListener(_scrollListener);
    _initWebSocketServer();
  }

  @override
  void dispose() {
    for (var conn in _portConnections.values) {
      conn.autoReconnect = false;
      conn.dispose();
    }
    _portConnections.clear();
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

    // 更新全局配置
    setState(() {
      globalBaudRate = baudRate.toString();
      globalDataBits = dataBits.toString();
      globalStopBits = stopBits.toString();
      globalParity = _convertParityToString(parity);
    });

    if (port.isEmpty || port == '*') {
      // 连接所有可用串口
      _connectAllPorts();
    } else {
      // 连接指定串口
      _connectPort(port);
    }

    // 发送响应
    bool anyConnected = _connectedPortCount > 0;
    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'connect',
      'success': anyConnected,
      'message': anyConnected ? '串口连接成功' : '串口连接失败',
      'port': port,
      'baudRate': baudRate
    });

    // 发送端口状态
    _sendPortStatus();
  }

  // 处理断开连接命令
  void _handleWebSocketDisconnectCommand(Map<String, dynamic> data) {
    String port = data['port'] ?? '';
    
    if (port.isEmpty || port == '*') {
      _disconnectAllPorts();
    } else {
      _disconnectPort(port);
    }

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'disconnect',
      'success': true,
      'message': port.isEmpty ? '所有串口已断开' : '串口 $port 已断开'
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
        globalBaudRate = data['baudRate'].toString();
      });
    }
    if (data.containsKey('dataBits')) {
      setState(() {
        globalDataBits = data['dataBits'].toString();
      });
    }
    if (data.containsKey('stopBits')) {
      setState(() {
        globalStopBits = data['stopBits'].toString();
      });
    }
    if (data.containsKey('parity')) {
      setState(() {
        globalParity = _convertParityToString(data['parity']);
      });
    }

    // 如果串口已连接，重新连接以应用新配置
    if (_connectedPortCount > 0) {
      _addLine("配置变更，请在串口列表中单独重连", LineType.system);
    }

    _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
      'command': 'set_config',
      'success': true,
      'message': '配置已更新',
      'config': {
        'baudRate': globalBaudRate,
        'dataBits': globalDataBits,
        'stopBits': globalStopBits,
        'parity': globalParity
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
    
    // 如果串口已连接，将WebSocket数据转发到所有已连接串口
    List<PortConnection> targets = _portConnections.values.where((p) => p.isConnected && p.serialPort != null).toList();
    if (targets.isEmpty) return;

    for (var conn in targets) {
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

        conn.serialPort!.write(dataToSend);
      } catch (e) {
        _addLine("转发WebSocket数据到${conn.portName}失败: $e", LineType.system);
      }
    }
  }

  // 发送串口状态
  void _sendPortStatus() {
    List<Map<String, dynamic>> ports = _portConnections.values.where((p) => p.isConnected).map((p) {
      return {
        'portName': p.portName,
        'portIndex': p.index,
        'baudRate': int.tryParse(p.baudRate) ?? 9600,
      };
    }).toList();
    _webSocketServer!.sendResponse(WebSocketResponseType.portStatus, {
      'connected': _connectedPortCount > 0,
      'ports': ports,
      'hexMode': hexMode,
      'chartMode': chartMode
    });
  }

  // 发送文本数据到所有已连接串口
  void _sendTextData(String message, {String port = ''}) {
    List<PortConnection> targets;
    if (port.isNotEmpty && _portConnections.containsKey(port)) {
      targets = [_portConnections[port]!];
    } else {
      targets = _portConnections.values.where((p) => p.isConnected && p.serialPort != null).toList();
    }

    if (targets.isEmpty) {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_text',
        'error': '串口未连接',
        'code': 4003
      });
      return;
    }

    bool allSuccess = true;
    for (var conn in targets) {
      try {
        Uint8List dataToSend = Uint8List.fromList(utf8.encode(message + '\r\n'));
        final bytesWritten = conn.serialPort!.write(dataToSend);
        if (bytesWritten == dataToSend.length) {
          _addLine(message, LineType.send);
        } else {
          allSuccess = false;
        }
      } catch (e) {
        allSuccess = false;
      }
    }

    if (allSuccess) {
      _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
        'command': 'send_text',
        'success': true,
        'message': '数据发送成功',
      });
    } else {
      _webSocketServer!.sendResponse(WebSocketResponseType.error, {
        'command': 'send_text',
        'error': '部分数据发送失败',
        'code': 4004
      });
    }
  }

  // 发送HEX数据到所有已连接串口
  void _sendHexData(String hexString) {
    List<PortConnection> targets = _portConnections.values.where((p) => p.isConnected && p.serialPort != null).toList();

    if (targets.isEmpty) {
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

      bool allSuccess = true;
      for (var conn in targets) {
        try {
          final bytesWritten = conn.serialPort!.write(dataToSend);
          if (bytesWritten == dataToSend.length) {
            String displayHex = cleanedData
                .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)} ')
                .trim();
            _addLine('HEX: $displayHex', LineType.send);
          } else {
            allSuccess = false;
          }
        } catch (e) {
          allSuccess = false;
        }
      }

      if (allSuccess) {
        String displayHex = cleanedData
            .replaceAllMapped(RegExp(r'.{2}'), (match) => '${match.group(0)} ')
            .trim();
        _webSocketServer!.sendResponse(WebSocketResponseType.commandResponse, {
          'command': 'send_hex',
          'success': true,
          'message': 'HEX数据发送成功',
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
  void _sendToWebSocket(String data, {int? portIndex}) {
    if (_webSocketServer != null && _isWebSocketServerRunning) {
      String prefix = portIndex != null ? '[$portIndex] ' : '';
      _webSocketServer!.broadcast('$prefix$data');
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
      if (_singleConnectPort.isEmpty && availablePorts.isNotEmpty) {
        _singleConnectPort = availablePorts.first;
      }
    });
  }

  void _connectPort(String portName, {bool manual = true}) {
    if (portName.isEmpty) return;

    PortConnection? existing = _portConnections[portName];
    if (existing != null && existing.isConnected) return;

    int index = existing?.index ?? _nextPortIndex;
    Color color = existing?.color ?? portColors[index % portColors.length];

    if (existing == null) {
      _nextPortIndex = index + 1;
    }

    PortConnection conn = existing ?? PortConnection(
      portName: portName,
      index: index,
      color: color,
      baudRate: globalBaudRate,
      dataBits: globalDataBits,
      stopBits: globalStopBits,
      parity: globalParity,
    );

    if (manual) conn.autoReconnect = true;

    try {
      conn.serialPort = SerialPort(portName);

      if (!conn.serialPort!.openReadWrite()) {
        _addLine("[!] $portName 被占用或无法打开，已跳过", LineType.system);
        conn.dispose();
        return;
      }

      final config = conn.serialPort!.config;
      config.baudRate = int.parse(conn.baudRate);
      config.bits = int.parse(conn.dataBits);
      config.parity = _getParityValue(conn.parity);
      config.stopBits = int.parse(conn.stopBits);
      conn.serialPort!.config = config;

      conn.reader = SerialPortReader(conn.serialPort!, timeout: 10);
      conn.subscription = conn.reader!.stream.listen(
        (data) => _onPortDataReceived(portName, data),
        onError: (e) => _handlePortDisconnect(portName),
        onDone: () => _handlePortDisconnect(portName),
      );

      conn.isConnected = true;
      _portConnections[portName] = conn;

      if (selectedSendPort.isEmpty) {
        selectedSendPort = portName;
      }

      _addLine(
        "[${conn.index}] $portName 连接成功 - ${conn.baudRate} ${conn.dataBits}${conn.parity}${conn.stopBits}",
        LineType.system,
      );

      setState(() {});
    } catch (e) {
      String err = e.toString().toLowerCase();
      if (err.contains('access') || err.contains('denied') || err.contains('busy') || 
          err.contains('occupied') || err.contains('in use') || err.contains('permission') ||
          err.contains('already open') || err.contains('被占用') || err.contains('无法打开')) {
        _addLine("[!] $portName ${manual ? '被占用，已跳过' : '无法连接'}", LineType.system);
      } else {
        _addLine("[!] $portName 连接失败: $e", LineType.system);
      }
      conn.dispose();
    }
  }

  void _connectAllPorts({bool skipOccupied = true}) {
    if (availablePorts.isEmpty) {
      _showMessage('没有检测到可用串口');
      return;
    }
    _addLine("正在连接所有可用串口 (${availablePorts.length}个)...", LineType.system);
    for (String port in availablePorts) {
      _connectPort(port, manual: true);
    }
    int connected = _connectedPortCount;
    int skipped = availablePorts.length - connected;
    if (skipped > 0) {
      _addLine("连接完成: $connected 个成功, $skipped 个被占用/跳过", LineType.system);
    } else {
      _addLine("连接完成: $connected 个串口已全部连接", LineType.system);
    }
  }

  void _handlePortDisconnect(String portName) {
    PortConnection? conn = _portConnections[portName];
    if (conn == null) return;

    conn.subscription?.cancel();
    conn.subscription = null;
    conn.reader?.close();
    conn.reader = null;
    conn.serialPort?.close();

    if (mounted) {
      setState(() {
        if (conn.autoReconnect) {
          conn.reconnectTimer?.cancel();
          conn.reconnectTimer = Timer(Duration(milliseconds: 10), () => _connectPort(portName, manual: false));
        } else {
          conn.isConnected = false;
          conn.serialPort?.dispose();
          conn.serialPort = null;
        }
      });
    }
  }

  void _disconnectPort(String portName) {
    PortConnection? conn = _portConnections[portName];
    if (conn == null) return;
    conn.autoReconnect = false;
    conn.reconnectTimer?.cancel();
    conn.dispose();

    if (selectedSendPort == portName) {
      var connected = _portConnections.values.where((p) => p.isConnected).toList();
      selectedSendPort = connected.isNotEmpty ? connected.first.portName : '';
    }

    setState(() {
      _portConnections.remove(portName);
    });
    _addLine("$portName 已断开", LineType.system);
  }

  void _disconnectAllPorts() {
    for (String portName in _portConnections.keys.toList()) {
      _disconnectPort(portName);
    }
  }

  void _onPortDataReceived(String portName, Uint8List data) {
    PortConnection? conn = _portConnections[portName];
    if (conn == null || data.isEmpty) return;

    try {
      String dataString = _tryMultipleDecodings(data);
      conn.dataBuffer.write(dataString);

      conn.dataTimeoutTimer?.cancel();
      conn.dataTimeoutTimer = Timer(
        Duration(milliseconds: _packetTimeout),
        () => _processPortBufferedData(portName),
      );

      if (conn.dataBuffer.length > _maxBufferLength) {
        _processPortBufferedData(portName);
      }
    } catch (e) {
      String hexString = data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();
      _displayReceivedData(hexString, portIndex: conn.index);
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

  // 添加增强的数据行（支持portIndex）
  void _addEnhancedLine(List<DataSegment> segments, LineType lineType, {int? portIndex}) {
    setState(() {
      _receivedEnhancedLines.add(EnhancedDataLine(
        segments: segments,
        lineType: lineType,
        timestamp: showTimestamp ? DateTime.now() : null,
        portIndex: portIndex,
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

  void _processPortBufferedData(String portName) {
    PortConnection? conn = _portConnections[portName];
    if (conn == null || conn.dataBuffer.isEmpty) return;

    String bufferedData = conn.dataBuffer.toString();
    conn.dataBuffer.clear();

    List<String> lines = _splitDataLines(bufferedData);

    for (String line in lines) {
      if (line.trim().isEmpty) continue;

      _displayReceivedData(line, portIndex: conn.index);

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

  void _displayReceivedData(String dataString, {int? portIndex}) {
    if (dataString.isEmpty) return;
    
    // 只有在HEX模式下才进行特殊处理，否则直接显示原始数据
    if (hexMode) {
      // 先处理不正常字符
      String processedString = _processUnusualCharacters(dataString);
      
      // 尝试将HEX格式转换为可读文本
      String convertedString = _convertHexToReadableText(processedString);
      
      // 使用智能分割算法处理混合数据
      List<DataSegment> segments = _splitTextAndHex(convertedString);
      _addEnhancedLine(segments, LineType.receive, portIndex: portIndex);
      _sendToWebSocket(convertedString, portIndex: portIndex);
    } else {
      // 非HEX模式下，直接处理原始数据，保留中文字符
      List<DataSegment> segments = _splitTextAndHex(dataString);
      _addEnhancedLine(segments, LineType.receive, portIndex: portIndex);
      _sendToWebSocket(dataString, portIndex: portIndex);
    }
  }

  void _sendData() {
    if (selectedSendPort.isEmpty || !_portConnections.containsKey(selectedSendPort)) {
      _showMessage('请先选择发送目标串口');
      return;
    }

    PortConnection conn = _portConnections[selectedSendPort]!;
    if (!conn.isConnected || conn.serialPort == null) {
      _showMessage('串口 ${conn.portName} 未连接');
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

      final bytesWritten = conn.serialPort!.write(dataToSend);

      if (bytesWritten == dataToSend.length) {
        // 发送数据时，同时添加到增强数据行列表以确保一致的显示
        List<DataSegment> segments = _splitTextAndHex(inputData);
        _addEnhancedLine(segments, LineType.send, portIndex: conn.index);
        _sendToWebSocket(inputData, portIndex: conn.index);
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

  void _copyAllDisplayContent() {
    StringBuffer allContent = StringBuffer();
    
    // 添加页面标题
    allContent.writeln('=== 串口通信页面内容 ===');
    allContent.writeln('时间: ${DateTime.now()}');
    allContent.writeln('连接端口数: $_connectedPortCount');
    if (_portConnections.isNotEmpty) {
      allContent.writeln('已连接串口:');
      for (var conn in _portConnections.values.where((p) => p.isConnected)) {
        allContent.writeln('  [${conn.index}] ${conn.portName} - ${conn.baudRate} ${conn.dataBits}${conn.parity}${conn.stopBits}');
      }
    }
    allContent.writeln('模式: ${hexMode ? "HEX模式" : "文本模式"} ${chartMode ? "图表模式" : ""}');
    allContent.writeln();
    
    // 添加接收的数据
    allContent.writeln('--- 接收的数据 (${_receivedEnhancedLines.isNotEmpty ? _receivedEnhancedLines.length : _receivedLines.length} 行) ---');
    if (_receivedEnhancedLines.isNotEmpty) {
      for (var line in _receivedEnhancedLines) {
        allContent.writeln(line.toString());
      }
    } else if (_receivedLines.isNotEmpty) {
      for (var line in _receivedLines) {
        allContent.writeln(line.toString());
      }
    } else {
      allContent.writeln('无数据');
    }
    allContent.writeln();
    
    // 添加图表数据（如果有）
    if (chartMode && dataKeys.isNotEmpty) {
      allContent.writeln('--- 图表数据 ---');
      for (String key in dataKeys) {
        if (chartData.containsKey(key) && chartData[key]!.isNotEmpty) {
          allContent.write('$key: ');
          List<FlSpot> points = chartData[key]!;
          for (int i = 0; i < points.length; i++) {
            if (i > 0) allContent.write(', ');
            allContent.write('(${points[i].x}, ${points[i].y})');
          }
          allContent.writeln();
        }
      }
      allContent.writeln();
    }
    
    // 添加WebSocket服务器状态
    if (_webSocketServer != null && _isWebSocketServerRunning) {
      allContent.writeln('--- WebSocket服务器状态 ---');
      allContent.writeln('端口: ${_webSocketServer!.port}');
      allContent.writeln('运行状态: 运行中');
      allContent.writeln();
    }
    
    String contentToCopy = allContent.toString();
    if (contentToCopy.trim().isNotEmpty) {
      Clipboard.setData(ClipboardData(text: contentToCopy));
      _showMessage('所有显示内容已复制到剪贴板');
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
        backgroundColor: _colors.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('动态串口图表工具', style: TextStyle(color: _colors.primary)),
        backgroundColor: _colors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.copy_all, color: _colors.primary),
            onPressed: _copyAllDisplayContent,
            tooltip: '复制所有显示内容',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: _colors.primary),
            onPressed: _refreshPortList,
            tooltip: '刷新串口列表',
          ),
          Container(
            margin: EdgeInsets.all(8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _connectedPortCount > 0 
                  ? Colors.green 
                  : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _connectedPortCount > 0 ? '已连 $_connectedPortCount' : '未连接',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Container(
        color: _colors.background,
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
    final displayLines = _monitorAllPorts || _selectedMonitorPort.isEmpty
        ? _receivedEnhancedLines
        : _receivedEnhancedLines.where((l) {
            int? targetIndex = _portConnections[_selectedMonitorPort]?.index;
            return targetIndex == null || l.portIndex == null || l.portIndex == targetIndex;
          }).toList();
    final filteredCount = displayLines.length;
    return Container(
      height: 250,
      decoration: BoxDecoration(
        border: Border.all(color: _colors.primary, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _colors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.input, color: _colors.primary, size: 16),
                SizedBox(width: 8),
                Text(
                  '接收的数据 ($filteredCount 行)',
                  style: TextStyle(
                    color: _colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Spacer(),
                Row(
                  children: [
                    // 各串口颜色图例
                    ..._portConnections.values.where((p) => p.isConnected).map((conn) {
                      return Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10, height: 10,
                              color: conn.color,
                              margin: EdgeInsets.only(right: 2),
                            ),
                            Text(
                              '[${conn.index}]',
                              style: TextStyle(color: conn.color, fontSize: 10),
                            ),
                          ],
                        ),
                      );
                    }),
                    Container(
                      width: 10,
                      height: 10,
                      color: _colors.receive,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text(
                      '接收',
                      style: TextStyle(color: _colors.text, fontSize: 10),
                    ),
                    SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      color: _colors.send,
                      margin: EdgeInsets.only(right: 4),
                    ),
                    Text(
                      '发送',
                      style: TextStyle(color: _colors.text, fontSize: 10),
                    ),
                    SizedBox(width: 16),
                  ],
                ),
                TextButton(
                  onPressed: _copyReceivedData,
                  child: Text(
                    '复制',
                    style: TextStyle(color: _colors.primary, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _clearReceivedData,
                  child: Text(
                    '清空',
                    style: TextStyle(color: _colors.primary, fontSize: 12),
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
                itemCount: filteredCount,
                itemBuilder: (context, index) {
                  return _buildEnhancedDataLine(displayLines[index], index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLine(DataLine dataLine, int index) {
    Color lineColor = _colors.text;

    switch (dataLine.type) {
      case LineType.send:
        lineColor = _colors.send;
        break;
      case LineType.receive:
        lineColor = _colors.receive;
        break;
      case LineType.system:
        lineColor = _colors.textSecondary;
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
    Color textColor = _colors.text;

    // 使用端口特定颜色
    if (dataLine.portIndex != null) {
      textColor = portColors[dataLine.portIndex! % portColors.length];
    } else {
      switch (dataLine.lineType) {
        case LineType.send:
          textColor = _colors.send;
          break;
        case LineType.receive:
          textColor = _colors.receive;
          break;
        case LineType.system:
          textColor = _colors.textSecondary;
          break;
      }
    }

    // 构建时间戳前缀（含端口号）
    String timePrefix = '';
    if (dataLine.timestamp != null && showTimestamp) {
      String timeStr = dataLine.timestamp!.toString().substring(11, 19);
      String portStr = dataLine.portIndex != null ? '[${dataLine.portIndex}] ' : '';
      switch (dataLine.lineType) {
        case LineType.send:
          timePrefix = '$timeStr ${portStr}发送: ';
          break;
        case LineType.receive:
          timePrefix = '$timeStr ${portStr}接收: ';
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
                    backgroundColor: _colors.hexBackground,
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
                  border: Border.all(color: _colors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Scrollbar(
                  controller: _inputScrollController,
                  thumbVisibility: true,
                  child: TextField(
                    onChanged: (value) => inputData = value,
                    controller: TextEditingController(text: inputData),
                    style: TextStyle(color: _colors.text),
                    maxLines: null,
                    scrollController: _inputScrollController,
                    decoration: InputDecoration(
                      hintText: hexMode
                          ? '输入HEX数据（如: 48 65 6C 6C 6F）'
                          : '输入要发送的文本',
                      hintStyle: TextStyle(color: _colors.textSecondary),
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
                  backgroundColor: _colors.background,
                  foregroundColor: _colors.primary,
                  side: BorderSide(
                    color: _colors.primary.withOpacity(0.7),
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
          border: Border.all(color: _colors.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _colors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.show_chart, color: _colors.primary, size: 16),
                  SizedBox(width: 8),
                  Text(
                    '动态数据图表',
                    style: TextStyle(
                      color: _colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: dataKeys.isEmpty
                        ? Container()
                        : Text(
                            '数据键: ${dataKeys.join(', ')}',
                            style: TextStyle(color: _colors.text, fontSize: 10),
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
                        style: TextStyle(color: _colors.textSecondary),
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
            Text('等待数据...', style: TextStyle(color: _colors.textSecondary)),
            SizedBox(height: 8),
            Text(
              '最新接收: ${_receivedLines.isNotEmpty ? _receivedLines.last.text : '无数据'}',
              style: TextStyle(color: _colors.textSecondary, fontSize: 12),
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
                      style: TextStyle(color: _colors.text, fontSize: 10),
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
                    style: TextStyle(color: _colors.text, fontSize: 10),
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
                color: _colors.textSecondary.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: _colors.textSecondary.withOpacity(0.1),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: _colors.primary.withOpacity(0.3), width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    final connectedPorts = _portConnections.values.where((p) => p.isConnected).toList();
    final monitorPortNames = connectedPorts.map((p) => p.portName).toList();
    if (!monitorPortNames.contains(_selectedMonitorPort)) {
      _selectedMonitorPort = monitorPortNames.isNotEmpty ? monitorPortNames.first : '';
    }
    return Container(
      width: 250,
      decoration: BoxDecoration(
        border: Border.all(color: _colors.primary.withOpacity(0.5), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 连接/断开所有按钮
            _buildConnectionButtons(),
            SizedBox(height: 16),

            // 串口列表
            Text('串口列表', style: TextStyle(color: _colors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ...availablePorts.map((port) => _buildPortItem(port)),

            SizedBox(height: 16),

            // 监控模式切换
            _buildMonitorToggle(),
            SizedBox(height: 12),

            // 单口监控选择
            if (!_monitorAllPorts && monitorPortNames.length > 1)
              _buildConfigItem('监视端口', _selectedMonitorPort, monitorPortNames),

            SizedBox(height: 12),

            // 连接目标
            _buildConnectionTargetSelector(),
            SizedBox(height: 12),

            // 全局配置
            _buildConfigItem('波特率', globalBaudRate, [
              '4800', '9600', '19200', '38400', '57600', '115200',
            ]),
            SizedBox(height: 12),
            _buildConfigItem('数据位', globalDataBits, ['5', '6', '7', '8']),
            SizedBox(height: 12),
            _buildConfigItem('停止位', globalStopBits, ['1', '1.5', '2']),
            SizedBox(height: 12),
            _buildConfigItem('校验码', globalParity, ['无校验', '奇校验', '偶校验', '标记', '空格']),
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

  Widget _buildConnectionButtons() {
    final hasConnections = _connectedPortCount > 0;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: hasConnections ? _performDisconnectByMode : _performConnectByMode,
            style: ElevatedButton.styleFrom(
              backgroundColor: hasConnections ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 8),
              side: BorderSide(
                color: hasConnections ? Colors.red.shade300 : Colors.green.shade300,
                width: 2,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(hasConnections ? Icons.close : Icons.usb, size: 16),
                SizedBox(width: 6),
                Text(hasConnections ? '断开连接' : '连接', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _performConnectByMode() {
    switch (_connectionMode) {
      case ConnectionMode.all:
        _connectAllPorts();
        break;
      case ConnectionMode.group:
        if (_groupPorts.isEmpty) {
          _showMessage('请先在串口列表中勾选要连接的端口');
          return;
        }
        for (String port in _groupPorts) {
          _connectPort(port);
        }
        break;
      case ConnectionMode.single:
        if (_singleConnectPort.isEmpty || !availablePorts.contains(_singleConnectPort)) {
          _showMessage('请选择要连接的串口');
          return;
        }
        _connectPort(_singleConnectPort);
        break;
    }
  }

  void _performDisconnectByMode() {
    switch (_connectionMode) {
      case ConnectionMode.all:
        _disconnectAllPorts();
        break;
      case ConnectionMode.group:
        if (_groupPorts.isEmpty) {
          _disconnectAllPorts();
          return;
        }
        for (String port in _groupPorts) {
          _disconnectPort(port);
        }
        break;
      case ConnectionMode.single:
        if (_singleConnectPort.isNotEmpty && _portConnections.containsKey(_singleConnectPort)) {
          _disconnectPort(_singleConnectPort);
        } else {
          _disconnectAllPorts();
        }
        break;
    }
  }

  Widget _buildPortItem(String portName) {
    PortConnection? conn = _portConnections[portName];
    bool isPortConnected = conn?.isConnected ?? false;
    Color portColor = conn?.color ?? Colors.grey;
    int? portIndex = conn?.index;
    bool inGroup = _groupPorts.contains(portName);

    return Container(
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPortConnected ? portColor : _colors.textSecondary.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // 分组模式下显示复选框
          if (_connectionMode == ConnectionMode.group && !isPortConnected)
            GestureDetector(
              onTap: () {
                setState(() {
                  if (inGroup) {
                    _groupPorts.remove(portName);
                  } else {
                    _groupPorts.add(portName);
                  }
                });
              },
              child: Container(
                margin: EdgeInsets.only(right: 6),
                child: Icon(
                  inGroup ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                  color: inGroup ? _colors.primary : _colors.textSecondary,
                ),
              ),
            ),
          // 颜色指示器
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isPortConnected ? portColor : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: isPortConnected ? portColor : _colors.textSecondary),
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              isPortConnected ? '[${portIndex}] $portName' : portName,
              style: TextStyle(
                color: isPortConnected ? portColor : _colors.textSecondary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 50,
            child: TextButton(
              onPressed: () {
                if (isPortConnected) {
                  _disconnectPort(portName);
                } else {
                  _connectPort(portName);
                }
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: isPortConnected ? Colors.red : Colors.green,
              ),
              child: Text(isPortConnected ? '断开' : '连接', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '监控模式',
          style: TextStyle(color: _colors.primary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            _monitorAllPorts ? '全部监控' : '单口监控',
            style: TextStyle(color: _colors.text, fontSize: 12),
          ),
          subtitle: Text(
            _monitorAllPorts ? '显示所有串口数据' : '仅显示选中串口数据',
            style: TextStyle(color: _colors.textSecondary, fontSize: 10),
          ),
          value: _monitorAllPorts,
          activeColor: _colors.primary,
          onChanged: (value) => setState(() => _monitorAllPorts = value),
        ),
      ],
    );
  }

  Widget _buildConnectionTargetSelector() {
    final modeLabels = {
      ConnectionMode.all: '全部',
      ConnectionMode.group: '分组',
      ConnectionMode.single: '单个',
    };
    final modeValues = ['全部', '分组', '单个'];
    String currentModeLabel = modeLabels[_connectionMode]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '连接目标',
          style: TextStyle(color: _colors.primary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4),
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: _colors.primary, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentModeLabel,
              isExpanded: true,
              dropdownColor: _colors.surface,
              style: TextStyle(color: _colors.text, fontSize: 12),
              icon: Icon(Icons.arrow_drop_down, color: _colors.primary),
              items: modeValues.map((String v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(v),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  if (newValue == '全部') _connectionMode = ConnectionMode.all;
                  else if (newValue == '分组') _connectionMode = ConnectionMode.group;
                  else if (newValue == '单个') _connectionMode = ConnectionMode.single;
                });
              },
            ),
          ),
        ),
        // 单个模式：显示串口选择
        if (_connectionMode == ConnectionMode.single)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: _buildConfigItem(
              '选择串口',
              _singleConnectPort,
              availablePorts.isEmpty ? ['无可用串口'] : availablePorts,
            ),
          ),
        // 分组模式提示
        if (_connectionMode == ConnectionMode.group)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              _groupPorts.isEmpty ? '勾选上方串口以选择' : '已选 ${_groupPorts.length} 个串口',
              style: TextStyle(color: _colors.textSecondary, fontSize: 10),
            ),
          ),
      ],
    );
  }

  Widget _buildConfigItem(String label, String value, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _colors.primary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: _colors.primary, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: _colors.surface,
              style: TextStyle(color: _colors.text, fontSize: 12),
              icon: Icon(Icons.arrow_drop_down, color: _colors.primary),
              items: options.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  if (label == '波特率') globalBaudRate = newValue!;
                  if (label == '数据位') globalDataBits = newValue!;
                  if (label == '停止位') globalStopBits = newValue!;
                  if (label == '校验码') globalParity = newValue!;
                  if (label == '选择串口') _singleConnectPort = newValue!;
                  if (label == '监视端口') _selectedMonitorPort = newValue!;
                });
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
            color: _colors.primary,
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
            style: TextStyle(color: _colors.text, fontSize: 12),
          ),
          value: hexMode,
          activeColor: _colors.primary,
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
            color: _colors.primary,
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
            style: TextStyle(color: _colors.text, fontSize: 12),
          ),
          value: showTimestamp,
          activeColor: _colors.primary,
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
          backgroundColor: _colors.surface,
          foregroundColor: _colors.primary,
          side: BorderSide(color: _colors.primary, width: 1.5),
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

// 串口端口颜色调色板 - 16种不同颜色
const List<Color> portColors = [
  Color(0xFF4EC9B0), // 端口0 - 青绿
  Color(0xFFCE9178), // 端口1 - 橙色
  Color(0xFF569CD6), // 端口2 - 蓝色
  Color(0xFFDCDCAA), // 端口3 - 黄色
  Color(0xFFC586C0), // 端口4 - 紫色
  Color(0xFFD16969), // 端口5 - 红色
  Color(0xFF9CDCFE), // 端口6 - 浅蓝
  Color(0xFFD7BA7D), // 端口7 - 金色
  Color(0xFF6A9955), // 端口8 - 绿色
  Color(0xFFCC7832), // 端口9 - 深橙
  Color(0xFFB5CEA8), // 端口10 - 浅绿
  Color(0xFFBD93F9), // 端口11 - 薰衣草
  Color(0xFF73C8A9), // 端口12 - 海绿
  Color(0xFFF08A5D), // 端口13 - 珊瑚
  Color(0xFFB83B5E), // 端口14 - 玫红
  Color(0xFF6C5B7B), // 端口15 - 紫灰
];

// 端口连接上下文类
class PortConnection {
  final String portName;
  final int index;
  final Color color;
  SerialPort? serialPort;
  SerialPortReader? reader;
  StreamSubscription<Uint8List>? subscription;
  bool isConnected;
  bool autoReconnect;
  Timer? reconnectTimer;
  StringBuffer dataBuffer;
  Timer? dataTimeoutTimer;
  String baudRate;
  String dataBits;
  String stopBits;
  String parity;

  PortConnection({
    required this.portName,
    required this.index,
    required this.color,
    this.baudRate = '9600',
    this.dataBits = '8',
    this.stopBits = '1',
    this.parity = '无校验',
    this.isConnected = false,
    this.autoReconnect = false,
  }) : dataBuffer = StringBuffer();

  void dispose() {
    subscription?.cancel();
    subscription = null;
    reader?.close();
    reader = null;
    serialPort?.close();
    serialPort?.dispose();
    serialPort = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    dataTimeoutTimer?.cancel();
    dataTimeoutTimer = null;
    dataBuffer.clear();
    isConnected = false;
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

// 连接模式定义
enum ConnectionMode { all, group, single }

// 增强的数据行类
class EnhancedDataLine {
  final List<DataSegment> segments;
  final LineType lineType;
  final DateTime? timestamp;
  final int? portIndex;
  
  EnhancedDataLine({
    required this.segments,
    required this.lineType,
    this.timestamp,
    this.portIndex,
  });
  
  @override
  String toString() {
    String content = segments.map((segment) => segment.content).join();
    String portStr = portIndex != null ? '[${portIndex}] ' : '';
    if (timestamp != null) {
      String timeStr = timestamp!.toString().substring(11, 19);
      switch (lineType) {
        case LineType.send:
          return '$timeStr ${portStr}发送: $content';
        case LineType.receive:
          return '$timeStr ${portStr}接收: $content';
        case LineType.system:
          return '$timeStr ${portStr}$content';
      }
    } else {
      return '$portStr$content';
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
