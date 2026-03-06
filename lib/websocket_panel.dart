import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'websocket_server.dart';

class WebSocketPanel extends StatefulWidget {
  final WebSocketServer? webSocketServer;
  final Function(String, String)? onSendData; // 添加发送数据回调

  const WebSocketPanel({
    Key? key,
    this.webSocketServer,
    this.onSendData,
  }) : super(key: key);

  @override
  _WebSocketPanelState createState() => _WebSocketPanelState();
}

class _WebSocketPanelState extends State<WebSocketPanel> {
  // 颜色常量定义
  static const Color vsCodeBackground = Color(0xFF1E1E1E);
  static const Color vsCodeSurface = Color(0xFF252526);
  static const Color vsCodeBlue = Color(0xFF569CD6);
  static const Color vsCodeText = Color(0xFFD4D4D4);
  static const Color vsCodeTextSecondary = Color(0xFF858585);
  static const Color receiveColor = Color(0xFF4EC9B0);
  static const Color sendColor = Color(0xFFCE9178);
  static const Color errorColor = Color(0xFFF48771);

  final List<LogEntry> _logEntries = [];
  final ScrollController _logScrollController = ScrollController();
  final int _maxLogEntries = 1000;

  // 串口相关变量
  List<String> _availablePorts = [];
  String _selectedPort = '';
  String _baudRate = '9600';
  bool _isConnected = false;
  bool _hexMode = false;
  bool _chartMode = false;
  
  String _sendText = '';
  String _sendHex = '';

  @override
  void initState() {
    super.initState();
    _addLogEntry('服务端控制面板已加载', LogType.system);
    _refreshPortList();
    
    // 添加WebSocket服务器命令回调
    if (widget.webSocketServer != null) {
      widget.webSocketServer!.addOnCommandCallback(_handleWebSocketCommandReceived);
      widget.webSocketServer!.addOnClientConnectCallback(_handleWebSocketClientConnect);
      widget.webSocketServer!.addOnClientDisconnectCallback(_handleWebSocketClientDisconnect);
    }
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  // 处理WebSocket服务器接收到的命令
  void _handleWebSocketCommandReceived(Map<String, dynamic> command) {
    String cmd = command['command'] ?? '';
    Map<String, dynamic> data = command['data'] ?? {};
    
    _addLogEntry('收到WebSocket命令: $cmd', LogType.command, command: jsonEncode(command));
    
    // 根据命令类型执行相应操作
    switch (cmd) {
      case 'connect':
        _handleConnectCommand(data);
        break;
      case 'disconnect':
        _handleDisconnectCommand(data);
        break;
      case 'send_text':
        _handleSendTextCommand(data);
        break;
      case 'send_hex':
        _handleSendHexCommand(data);
        break;
      case 'list_ports':
        _handleListPortsCommand(data);
        break;
      case 'set_hex_mode':
        _handleSetHexModeCommand(data);
        break;
      case 'set_chart_mode':
        _handleSetChartModeCommand(data);
        break;
      default:
        _addLogEntry('未知命令: $cmd', LogType.error);
    }
  }

  void _handleConnectCommand(Map<String, dynamic> data) {
    String port = data['port'] ?? '';
    int baudRate = data['baudRate'] ?? 9600;
    
    if (port.isEmpty) {
      _addLogEntry('串口连接失败: 串口未指定', LogType.error);
      return;
    }
    
    // 更新UI状态
    setState(() {
      _selectedPort = port;
      _baudRate = baudRate.toString();
      _isConnected = true;
    });
    
    _addLogEntry('串口连接命令执行: $port@$baudRate', LogType.system);
    
    // 通知主应用连接串口
    widget.onSendData?.call('connect', jsonEncode({
      'port': port,
      'baudRate': baudRate,
      'dataBits': 8,
      'stopBits': 1,
      'parity': 'none'
    }));
  }

  void _handleDisconnectCommand(Map<String, dynamic> data) {
    setState(() {
      _isConnected = false;
    });
    
    _addLogEntry('串口断开命令执行', LogType.system);
    
    // 通知主应用断开串口
    widget.onSendData?.call('disconnect', '');
  }

  void _handleSendTextCommand(Map<String, dynamic> data) {
    String message = data['message'] ?? '';
    
    _addLogEntry('发送文本命令: $message', LogType.command);
    
    // 通知主应用发送文本数据
    widget.onSendData?.call('send_text', message);
  }

  void _handleSendHexCommand(Map<String, dynamic> data) {
    String hex = data['hex'] ?? '';
    
    _addLogEntry('发送HEX命令: $hex', LogType.command);
    
    // 通知主应用发送HEX数据
    widget.onSendData?.call('send_hex', hex);
  }

  void _handleListPortsCommand(Map<String, dynamic> data) {
    _refreshPortList();
    _addLogEntry('列出串口命令执行', LogType.system);
  }

  void _handleSetHexModeCommand(Map<String, dynamic> data) {
    bool enabled = data['enabled'] ?? false;
    
    setState(() {
      _hexMode = enabled;
    });
    
    _addLogEntry('设置HEX模式: ${enabled ? '启用' : '禁用'}', LogType.system);
    
    // 通知主应用设置HEX模式
    widget.onSendData?.call('set_hex_mode', jsonEncode({'enabled': enabled}));
  }

  void _handleSetChartModeCommand(Map<String, dynamic> data) {
    bool enabled = data['enabled'] ?? false;
    
    setState(() {
      _chartMode = enabled;
    });
    
    _addLogEntry('设置图表模式: ${enabled ? '启用' : '禁用'}', LogType.system);
    
    // 通知主应用设置图表模式
    widget.onSendData?.call('set_chart_mode', jsonEncode({'enabled': enabled}));
  }

  // 处理WebSocket客户端连接
  void _handleWebSocketClientConnect(String clientInfo) {
    _addLogEntry('WebSocket客户端连接: $clientInfo', LogType.system);
    setState(() {
      // WebSocket客户端连接不影响串口连接状态
    });
  }

  // 处理WebSocket客户端断开连接
  void _handleWebSocketClientDisconnect(String clientInfo) {
    _addLogEntry('WebSocket客户端断开: $clientInfo', LogType.system);
    setState(() {
      // WebSocket客户端断开不影响串口连接状态
    });
  }

  void _addLogEntry(String message, LogType type, {String? command, String? response}) {
    setState(() {
      _logEntries.add(LogEntry(
        message: message,
        type: type,
        command: command,
        response: response,
        timestamp: DateTime.now(),
      ));

      if (_logEntries.length > _maxLogEntries) {
        _logEntries.removeRange(0, _logEntries.length - _maxLogEntries);
      }
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _refreshPortList() {
    setState(() {
      _availablePorts = SerialPort.availablePorts;
      if (_availablePorts.isNotEmpty && _selectedPort.isEmpty) {
        _selectedPort = _availablePorts.first;
      }
    });
  }

  void _connectToPort() {
    if (_selectedPort.isEmpty) {
      _addLogEntry('请选择串口', LogType.error);
      return;
    }

    int baudRate = int.tryParse(_baudRate) ?? 9600;
    
    // 更新UI状态
    setState(() {
      _isConnected = true;
    });
    
    _addLogEntry('连接串口: $_selectedPort@$baudRate', LogType.system);

    // 通知主应用连接串口
    widget.onSendData?.call('connect', jsonEncode({
      'port': _selectedPort,
      'baudRate': baudRate,
      'dataBits': 8,
      'stopBits': 1,
      'parity': 'none'
    }));
  }

  void _disconnectPort() {
    // 更新UI状态
    setState(() {
      _isConnected = false;
    });
    
    _addLogEntry('断开串口连接', LogType.system);

    // 通知主应用断开串口
    widget.onSendData?.call('disconnect', '');
  }

  void _sendTextData() {
    if (_sendText.isEmpty) {
      _addLogEntry('请输入要发送的文本', LogType.error);
      return;
    }

    _addLogEntry('发送文本: $_sendText', LogType.command);

    // 通知主应用发送文本数据
    widget.onSendData?.call('send_text', _sendText);

    setState(() {
      _sendText = '';
    });
  }

  void _sendHexData() {
    if (_sendHex.isEmpty) {
      _addLogEntry('请输入HEX数据', LogType.error);
      return;
    }

    _addLogEntry('发送HEX: $_sendHex', LogType.command);

    // 通知主应用发送HEX数据
    widget.onSendData?.call('send_hex', _sendHex);

    setState(() {
      _sendHex = '';
    });
  }

  void _listPorts() {
    _refreshPortList();
    _addLogEntry('刷新串口列表: ${_availablePorts.length} 个串口可用', LogType.system);
  }

  void _setHexMode(bool enabled) {
    setState(() {
      _hexMode = enabled;
    });
    
    _addLogEntry('设置HEX模式: ${enabled ? '启用' : '禁用'}', LogType.system);
    
    // 通知主应用设置HEX模式
    widget.onSendData?.call('set_hex_mode', jsonEncode({'enabled': enabled}));
  }

  void _setChartMode(bool enabled) {
    setState(() {
      _chartMode = enabled;
    });
    
    _addLogEntry('设置图表模式: ${enabled ? '启用' : '禁用'}', LogType.system);
    
    // 通知主应用设置图表模式
    widget.onSendData?.call('set_chart_mode', jsonEncode({'enabled': enabled}));
  }

  void _clearLog() {
    setState(() {
      _logEntries.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: vsCodeBackground,
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // WebSocket服务器状态区域
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: vsCodeBlue, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WebSocket服务器状态',
                  style: TextStyle(
                    color: vsCodeBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: '服务器端口',
                          labelStyle: TextStyle(color: vsCodeTextSecondary),
                          hintText: '例如: 9090',
                          hintStyle: TextStyle(color: vsCodeTextSecondary),
                          filled: true,
                          fillColor: vsCodeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue, width: 2),
                          ),
                        ),
                        style: TextStyle(color: vsCodeText),
                        controller: TextEditingController(text: widget.webSocketServer?.port.toString() ?? '9090'),
                        enabled: false, // 端口由主应用管理，不可编辑
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 120,
                      child: ElevatedButton(
                        onPressed: null, // 服务器状态由主应用管理
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text('运行中'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'WebSocket服务器运行中: ${widget.webSocketServer?.port ?? '未知'}',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: vsCodeSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: vsCodeBlue,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '客户端连接数: ${widget.webSocketServer?.getClientCount() ?? 0}',
                        style: TextStyle(
                          color: vsCodeText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // 串口控制区域
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: vsCodeBlue, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '串口控制',
                  style: TextStyle(
                    color: vsCodeBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),

                // 串口选择和配置
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: '串口号',
                          labelStyle: TextStyle(color: vsCodeTextSecondary),
                          hintText: '例如: /dev/ttyUSB0',
                          hintStyle: TextStyle(color: vsCodeTextSecondary),
                          filled: true,
                          fillColor: vsCodeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue, width: 2),
                          ),
                        ),
                        style: TextStyle(color: vsCodeText),
                        controller: TextEditingController(text: _selectedPort),
                        onChanged: (value) => setState(() => _selectedPort = value),
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 100,
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: '波特率',
                          labelStyle: TextStyle(color: vsCodeTextSecondary),
                          filled: true,
                          fillColor: vsCodeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue, width: 2),
                          ),
                        ),
                        style: TextStyle(color: vsCodeText),
                        controller: TextEditingController(text: _baudRate),
                        onChanged: (value) => setState(() => _baudRate = value),
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 100,
                      child: ElevatedButton(
                        onPressed: _isConnected ? _disconnectPort : _connectToPort,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                          side: BorderSide(color: vsCodeBlue, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text(_isConnected ? '断开串口' : '连接串口'),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 12),

                // 快速命令按钮
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _listPorts,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vsCodeSurface,
                        foregroundColor: vsCodeBlue,
                        side: BorderSide(color: vsCodeBlue, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('刷新串口'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setHexMode(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hexMode ? vsCodeSurface : vsCodeBlue,
                        foregroundColor: _hexMode ? vsCodeBlue : Colors.white,
                        side: BorderSide(color: vsCodeBlue, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('文本模式'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setHexMode(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hexMode ? vsCodeBlue : vsCodeSurface,
                        foregroundColor: _hexMode ? Colors.white : vsCodeBlue,
                        side: BorderSide(color: vsCodeBlue, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('HEX模式'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setChartMode(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _chartMode ? vsCodeBlue : vsCodeSurface,
                        foregroundColor: _chartMode ? Colors.white : vsCodeBlue,
                        side: BorderSide(color: vsCodeBlue, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('开启图表'),
                    ),
                    ElevatedButton(
                      onPressed: () => _setChartMode(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _chartMode ? vsCodeSurface : vsCodeBlue,
                        foregroundColor: _chartMode ? vsCodeBlue : Colors.white,
                        side: BorderSide(color: vsCodeBlue, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text('关闭图表'),
                    ),
                  ],
                ),

                SizedBox(height: 12),

                // 数据发送区域
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: '发送文本',
                          labelStyle: TextStyle(color: vsCodeTextSecondary),
                          hintText: '输入要发送的文本',
                          hintStyle: TextStyle(color: vsCodeTextSecondary),
                          filled: true,
                          fillColor: vsCodeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue, width: 2),
                          ),
                        ),
                        style: TextStyle(color: vsCodeText),
                        controller: TextEditingController(text: _sendText),
                        onChanged: (value) => setState(() => _sendText = value),
                        onSubmitted: (_) => _sendTextData(),
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 80,
                      child: ElevatedButton(
                        onPressed: _sendTextData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vsCodeSurface,
                          foregroundColor: vsCodeBlue,
                          side: BorderSide(color: vsCodeBlue, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text('发送'),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: '发送HEX',
                          labelStyle: TextStyle(color: vsCodeTextSecondary),
                          hintText: '输入HEX数据 (如: 48656C6C6F)',
                          hintStyle: TextStyle(color: vsCodeTextSecondary),
                          filled: true,
                          fillColor: vsCodeSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: vsCodeBlue, width: 2),
                          ),
                        ),
                        style: TextStyle(color: vsCodeText),
                        controller: TextEditingController(text: _sendHex),
                        onChanged: (value) => setState(() => _sendHex = value),
                        onSubmitted: (_) => _sendHexData(),
                      ),
                    ),
                    SizedBox(width: 12),
                    Container(
                      width: 80,
                      child: ElevatedButton(
                        onPressed: _sendHexData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vsCodeSurface,
                          foregroundColor: vsCodeBlue,
                          side: BorderSide(color: vsCodeBlue, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: Text('发送'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // 日志显示区域
          Expanded(
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
                        Icon(Icons.list, color: vsCodeBlue, size: 16),
                        SizedBox(width: 8),
                        Text(
                          '服务端日志',
                          style: TextStyle(
                            color: vsCodeBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        TextButton(
                          onPressed: _clearLog,
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
                      controller: _logScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _logScrollController,
                        itemCount: _logEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _logEntries[index];
                          Color entryColor = vsCodeText;

                          switch (entry.type) {
                            case LogType.command:
                              entryColor = sendColor;
                              break;
                            case LogType.response:
                              entryColor = receiveColor;
                              break;
                            case LogType.error:
                              entryColor = errorColor;
                              break;
                            case LogType.system:
                              entryColor = vsCodeTextSecondary;
                              break;
                          }

                          return Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: entryColor,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${entry.timestamp!.hour.toString().padLeft(2, '0')}:${entry.timestamp!.minute.toString().padLeft(2, '0')}:${entry.timestamp!.second.toString().padLeft(2, '0')}] ${entry.message}',
                                  style: TextStyle(color: entryColor, fontSize: 12),
                                ),
                                if (entry.command != null) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    '命令: ${entry.command}',
                                    style: TextStyle(color: sendColor, fontSize: 10),
                                  ),
                                ],
                                if (entry.response != null) ...[
                                  SizedBox(height: 4),
                                  Text(
                                    '响应: ${entry.response}',
                                    style: TextStyle(color: receiveColor, fontSize: 10),
                                  ),
                                ],
                              ],
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
    );
  }

  // 从父组件接收日志更新
  void updateLog(String message, LogType type, {String? command, String? response}) {
    _addLogEntry(message, type, command: command, response: response);
  }

  void updateConnectionStatus(bool connected) {
    setState(() {
      _isConnected = connected;
    });
  }
}

enum LogType { command, response, error, system }

class LogEntry {
  final String message;
  final LogType type;
  final String? command;
  final String? response;
  final DateTime? timestamp;

  LogEntry({
    required this.message,
    required this.type,
    this.command,
    this.response,
    this.timestamp,
  });
}
