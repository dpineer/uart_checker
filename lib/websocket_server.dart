import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

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
  static const int DEFAULT_PORT = 8080;
  late HttpServer _server;
  final List<_WebSocketClient> _clients = [];
  final List<Function(String data)> _onReceiveCallbacks = [];
  final List<Function(String clientInfo)> _onClientConnectCallbacks = [];
  final List<Function(String clientInfo)> _onClientDisconnectCallbacks = [];
  bool _isRunning = false;

  int get port => _server.port;

  // 添加端口数据接收回调
  void addOnReceiveCallback(Function(String data) callback) {
    _onReceiveCallbacks.add(callback);
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

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;
      print('WebSocket服务器启动在端口: $port');

      _server.listen(
        _handleHttpRequest,
        onError: (error) {
          print('WebSocket服务器错误: $error');
        },
      );
    } catch (e) {
      print('启动WebSocket服务器失败: $e');
      rethrow;
    }
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
            // 调用所有注册的回调函数
            for (var callback in _onReceiveCallbacks) {
              callback(data);
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
}
