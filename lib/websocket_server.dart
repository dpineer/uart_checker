import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

// 命令类型枚举
enum WebSocketCommand {
  connect,
  disconnect,
  listPorts,
  sendText,
  sendHex,
  setConfig,
  setHexMode,
  setChartMode,
  unknown
}

// 响应类型枚举
enum WebSocketResponseType {
  commandResponse,
  serialData,
  systemMessage,
  portStatus,
  error
}

// 内部类用于存储WebSocket客户端及其连接信息
class _WebSocketClient {
  final WebSocket webSocket;
  final String ipAddress;
  final int port;

  _WebSocketClient(this.webSocket, this.ipAddress, this.port);

  // 代理WebSocket的方法
  void add(dynamic data) {
    webSocket.add(data);
  }

  void close({int? code, String? reason}) {
    webSocket.close(code, reason);
  }
}

class WebSocketServer {
  static const int DEFAULT_PORT = 9090;
  late HttpServer _server;
  final List<_WebSocketClient> _clients = [];
  final List<Function(Map<String, dynamic> command)> _onCommandCallbacks = [];
  final List<Function(String clientInfo)> _onClientConnectCallbacks = [];
  final List<Function(String clientInfo)> _onClientDisconnectCallbacks = [];
  bool _isRunning = false;
  int _currentPort = DEFAULT_PORT;

  int get port => _currentPort;

  // 添加命令接收回调（新API）
  void addOnCommandCallback(Function(Map<String, dynamic> command) callback) {
    _onCommandCallbacks.add(callback);
  }

  // 添加数据接收回调（旧API，用于向后兼容）
  void addOnReceiveCallback(Function(String data) callback) {
    // 包装旧的回调函数以适应新的命令回调格式
    addOnCommandCallback((command) {
      // 如果是原始数据命令，调用旧的回调
      if (command['command'] == 'raw_data' && command['data'] is Map) {
        String message = command['data']['message'] ?? '';
        callback(message);
      }
    });
  }

  // 添加客户端连接回调
  void addOnClientConnectCallback(Function(String clientInfo) callback) {
    _onClientConnectCallbacks.add(callback);
  }

  // 添加客户端断开连接回调
  void addOnClientDisconnectCallback(Function(String clientInfo) callback) {
    _onClientDisconnectCallbacks.add(callback);
  }

  Future<void> start({int port = DEFAULT_PORT}) async {
    if (_isRunning) {
      print('WebSocket服务器已在端口 ${_server.port} 上运行');
      return;
    }

    // 尝试启动WebSocket服务器，如果指定端口被占用则自动尝试其他端口
    int currentPort = port;
    int maxAttempts = 10; // 最多尝试10个端口
    int attempts = 0;

    while (attempts < maxAttempts) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, currentPort);
        _currentPort = currentPort;
        _isRunning = true;
        print('WebSocket服务器启动在端口: $currentPort');
        break; // 成功启动，退出循环
      } catch (e) {
        attempts++;
        print('启动WebSocket服务器失败 (端口 $currentPort): $e');
        if (attempts < maxAttempts) {
          currentPort++; // 尝试下一个端口
          print('尝试下一个端口: $currentPort');
        } else {
          print('已尝试 $maxAttempts 个端口，全部失败');
          rethrow;
        }
      }
    }

    _server.listen(
      _handleHttpRequest,
      onError: (error) {
        print('WebSocket服务器错误: $error');
      },
    );
  }

  void _handleHttpRequest(HttpRequest request) {
    // 检查是否是WebSocket升级请求
    if (request.headers.value('upgrade')?.toLowerCase() == 'websocket') {
      WebSocketTransformer.upgrade(request).then((webSocket) {
        // 保存客户端连接信息
        final ipAddress = request.connectionInfo?.remoteAddress.address ?? 'unknown';
        final port = request.connectionInfo?.remotePort ?? 0;
        final client = _WebSocketClient(webSocket, ipAddress, port);
        _clients.add(client);

        // 通知客户端连接
        final clientInfo = '客户端IP: $ipAddress, 端口: $port';
        print('新WebSocket客户端连接: $clientInfo');
        for (var callback in _onClientConnectCallbacks) {
          callback(clientInfo);
        }

        // 监听客户端消息
        webSocket.listen(
          (data) {
            print('收到WebSocket数据: $data');
            // 尝试解析JSON命令
            try {
              final jsonData = jsonDecode(data);
              if (jsonData is Map<String, dynamic>) {
                // 调用所有注册的命令回调函数
                for (var callback in _onCommandCallbacks) {
                  callback(jsonData);
                }
              } else {
                print('收到的数据不是有效的JSON对象: $data');
              }
            } catch (e) {
              print('解析WebSocket数据失败: $e, 数据: $data');
              // 如果不是JSON格式，仍然尝试调用旧的回调（用于向后兼容）
              for (var callback in _onCommandCallbacks) {
                callback({'command': 'raw_data', 'data': {'message': data}});
              }
            }
          },
          onError: (error) {
            print('WebSocket客户端错误: $error');
          },
          onDone: () {
            // 客户端断开连接
            _clients.remove(client);
            webSocket.close();

            final clientInfo = '客户端IP: $ipAddress, 端口: $port';
            print('WebSocket客户端断开连接: $clientInfo');
            for (var callback in _onClientDisconnectCallbacks) {
              callback(clientInfo);
            }
          },
        );
      }).catchError((error) {
        print('WebSocket升级错误: $error');
      });
    } else {
      // 非WebSocket请求，返回错误
      request.response.statusCode = 400;
      request.response.write('This is a WebSocket server. Connect using a WebSocket client.');
      request.response.close();
    }
  }

  void broadcast(String message) {
    if (!_isRunning) {
      print('WebSocket服务器未运行');
      return;
    }

    // 向所有客户端广播消息
    for (var client in _clients) {
      try {
        client.add(message);
      } catch (e) {
        print('向客户端发送消息失败: $e');
        // 如果发送失败，移除该客户端
        _clients.remove(client);
      }
    }
  }

  void broadcastJson(Map<String, dynamic> data) {
    if (!_isRunning) {
      print('WebSocket服务器未运行');
      return;
    }

    // 将JSON数据转换为字符串并广播
    String jsonString = jsonEncode(data);
    broadcast(jsonString);
  }

  void sendToClient(int clientIndex, String message) {
    if (!_isRunning) {
      print('WebSocket服务器未运行');
      return;
    }

    if (clientIndex >= 0 && clientIndex < _clients.length) {
      try {
        _clients[clientIndex].add(message);
      } catch (e) {
        print('向客户端发送消息失败: $e');
        _clients.removeAt(clientIndex);
      }
    } else {
      print('无效的客户端索引: $clientIndex');
    }
  }

  void sendJsonToClient(int clientIndex, Map<String, dynamic> data) {
    if (!_isRunning) {
      print('WebSocket服务器未运行');
      return;
    }

    String jsonString = jsonEncode(data);
    sendToClient(clientIndex, jsonString);
  }

  List<String> getClientList() {
    // 返回客户端连接信息
    List<String> clients = [];
    for (int i = 0; i < _clients.length; i++) {
      clients.add('WebSocket客户端 #$i');
    }
    return clients;
  }

  int getClientCount() {
    return _clients.length;
  }

  Future<void> stop() async {
    if (!_isRunning) {
      print('WebSocket服务器未运行');
      return;
    }

    // 关闭所有客户端连接
    for (var client in _clients) {
      try {
        client.close();
      } catch (e) {
        print('关闭客户端连接时出错: $e');
      }
    }
    _clients.clear();

    // 关闭服务器
    await _server.close();
    _isRunning = false;
    print('WebSocket服务器已停止');
  }

  bool get isRunning => _isRunning;

  // 解析命令字符串为枚举
  WebSocketCommand parseCommand(String commandStr) {
    switch (commandStr.toLowerCase()) {
      case 'connect':
        return WebSocketCommand.connect;
      case 'disconnect':
        return WebSocketCommand.disconnect;
      case 'list_ports':
        return WebSocketCommand.listPorts;
      case 'send_text':
        return WebSocketCommand.sendText;
      case 'send_hex':
        return WebSocketCommand.sendHex;
      case 'set_config':
        return WebSocketCommand.setConfig;
      case 'set_hex_mode':
        return WebSocketCommand.setHexMode;
      case 'set_chart_mode':
        return WebSocketCommand.setChartMode;
      default:
        return WebSocketCommand.unknown;
    }
  }

  // 发送响应到所有客户端
  void sendResponse(WebSocketResponseType type, Map<String, dynamic> data) {
    Map<String, dynamic> response = {
      'type': _getResponseTypeString(type),
      'data': data,
      'timestamp': DateTime.now().toIso8601String()
    };
    broadcastJson(response);
  }

  // 获取响应类型字符串
  String _getResponseTypeString(WebSocketResponseType type) {
    switch (type) {
      case WebSocketResponseType.commandResponse:
        return 'command_response';
      case WebSocketResponseType.serialData:
        return 'serial_data';
      case WebSocketResponseType.systemMessage:
        return 'system_message';
      case WebSocketResponseType.portStatus:
        return 'port_status';
      case WebSocketResponseType.error:
        return 'error';
      default:
        return 'unknown';
    }
  }
}
