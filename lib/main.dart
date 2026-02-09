import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:selectable/selectable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:quick_usb/quick_usb.dart' as quick_usb;
import 'usb_packet_tab.dart';

void main() async { // <--- 将 main 函数标记为 async
  // 在运行应用之前，确保插件系统已初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 核心修复：在这里初始化 quick_usb 插件，并等待其完成
  await _initQuickUsb();
  
  runApp(CommunicationToolApp());
}

Future<void> _initQuickUsb() async {
  try {
    print('正在初始化 QuickUsb...');
    // 调用插件提供的初始化方法
    bool success = await quick_usb.QuickUsb.init(); 
    if (!success) {
      // 如果 init 返回 false，手动抛出一个错误，让上面 catch 住
      throw Exception('底层库初始化返回 false，插件实例未正确创建');
    }
    print('QuickUsb 初始化成功');
  } catch (e) {
    print('USB库初始化发生异常: $e');
    
    // 提供更详细的诊断信息，特别是对于 Linux
    if (e.toString().contains('LateInitializationError')) {
      print('错误诊断: QuickUsbPlatform.instance 未初始化，这通常意味着插件初始化失败。');
      print('可能原因: 插件内部注册失败或平台特定实现加载失败');
      print('请确保您的应用程序在启动时正确调用 quick_usb.QuickUsb.init()。');
    } else if (Platform.isLinux && e.toString().contains('libusb')) {
      print('错误提示: 在 Linux 环境下，可能缺少 libusb 库文件。');
      print('解决方案: 请尝试运行命令: sudo apt update && sudo apt install libusb-1.0-0-dev');
    } else {
      print('其他错误: 请检查 QuickUsb 插件的配置和系统环境。');
    }
  }
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
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('通信工具', style: TextStyle(color: Color(0xFF569CD6))),
        backgroundColor: Color(0xFF1E1E1E),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.settings_input_component, size: 20),
              text: '串口通信',
            ),
            Tab(
              icon: Icon(Icons.usb, size: 20),
              text: 'USB报文解析',
            ),
          ],
          labelColor: Color(0xFF569CD6),
          unselectedLabelColor: Color(0xFF858585),
          indicatorColor: Color(0xFF569CD6),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SerialPortHomePage(),
          UsbPacketTab(),
        ],
      ),
    );
  }
}

class SerialPortHomePage extends StatefulWidget {
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
  static const Color vsCodeOrange = Color(0xFFCE9178);
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

  @override
  void initState() {
    super.initState();
    _refreshPortList();
    _addLine("等待接收数据...", LineType.system);
    _receiveScrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _reader?.close();
    _serialPort?.close();
    _serialPort?.dispose();
    _dataTimeoutTimer?.cancel();
    _dataBuffer.clear();
    _receiveScrollController.dispose();
    super.dispose();
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
        _receiveScrollController.animateTo(
          _receiveScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
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

  void _connect() async {
    if (selectedPort.isEmpty) {
      _showMessage('请选择串口');
      return;
    }

    try {
      _serialPort = SerialPort(selectedPort);

      // 先打开串口[6](@ref)
      if (!_serialPort!.openReadWrite()) {
        _showMessage('打开串口失败: ${SerialPort.lastError}');
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
      _subscription = _reader!.stream.listen(_onDataReceived);

      setState(() {
        isConnected = true;
      });

      _addLine(
        "串口连接成功 - 波特率: $selectedBaudRate, 数据位: $selectedDataBits, 停止位: $selectedStopBits, 校验: $selectedParity",
        LineType.system,
      );
      _showMessage('串口连接成功');
    } catch (e) {
      _showMessage('连接失败: $e');
    }
  }

  void _disconnect() {
    _subscription?.cancel();
    _reader?.close();
    _serialPort?.close();
    _serialPort?.dispose();
    _dataTimeoutTimer?.cancel();
    _dataBuffer.clear();

    setState(() {
      isConnected = false;
    });

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
    // 首先尝试UTF-8解码
    try {
      String result = utf8.decode(data, allowMalformed: false);
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
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      if (code >= 32 && code <= 126 || code == 10 || code == 13 || code == 9) {
        printableCount++;
      }
    }

    double printableRatio = printableCount / text.length;
    return printableRatio > 0.7; // 如果可打印字符超过70%，认为是有效文本
  }

  // 判断字符是否为HEX字符
  bool _isHexCharacter(String char) {
    if (char.length != 1) return false;
    return RegExp(r'[0-9A-Fa-f]').hasMatch(char);
  }

  // 判断字符是否为正常字符（ASCII可打印字符+常见控制字符）
  bool _isNormalCharacter(int codePoint) {
    // ASCII可打印字符（包括空格、标点、数字、字母）
    if (codePoint >= 32 && codePoint <= 126) return true;
    
    // 常见控制字符：换行、回车、制表符
    if (codePoint == 10 || codePoint == 13 || codePoint == 9) return true;
    
    // 扩展ASCII中的常见符号（如°、±等）
    // 这里可以扩展更多常见符号
    
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
    
    // 先处理不正常字符
    String processedString = _processUnusualCharacters(dataString);
    
    // 使用智能分割算法处理混合数据
    List<DataSegment> segments = _splitTextAndHex(processedString);
    _addEnhancedLine(segments, LineType.receive);
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
        _addLine(inputData, LineType.send);
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
    if (_receivedLines.isEmpty) {
      _showMessage('没有可复制的内容');
      return;
    }

    String textToCopy = _receivedLines
        .map((line) => line.toString())
        .join('\n');
    Clipboard.setData(ClipboardData(text: textToCopy));
    _showMessage('内容已复制到剪贴板 (${_receivedLines.length} 行)');
  }

  void _clearReceivedData() {
    setState(() {
      _receivedLines.clear();
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
              color: isConnected ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isConnected ? '已连接' : '未连接',
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
              onChanged: isConnected
                  ? null
                  : (newValue) {
                      setState(() {
                        if (label == '串口号') selectedPort = newValue!;
                        if (label == '波特率') selectedBaudRate = newValue!;
                        if (label == '数据位') selectedDataBits = newValue!;
                        if (label == '停止位') selectedStopBits = newValue!;
                        if (label == '校验码') selectedParity = newValue!;
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
