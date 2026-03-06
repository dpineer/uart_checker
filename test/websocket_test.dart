import 'dart:io';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:test/test.dart';
import '../lib/websocket_server.dart';

void main() {
  group('WebSocketServer Tests', () {
    WebSocketServer? server;
    late int port;

    setUp(() async {
      server = WebSocketServer();
      await server!.start(port: 0); // 使用随机端口
      port = server!.port;
    });

    tearDown(() async {
      await server?.stop();
    });

    test('WebSocket服务器启动和停止', () async {
      expect(server!.isRunning, true);
      expect(port, greaterThan(0));

      await server!.stop();
      expect(server!.isRunning, false);
      
    });

    test('WebSocket客户端连接和断开', () async {
      int connectCount = 0;
      int disconnectCount = 0;
      String lastClientInfo = '';

      server!.addOnClientConnectCallback((clientInfo) {
        connectCount++;
        lastClientInfo = clientInfo;
      });

      server!.addOnClientDisconnectCallback((clientInfo) {
        disconnectCount++;
      });

      // 连接WebSocket客户端
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 等待连接回调
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(connectCount, 1);
      expect(lastClientInfo.contains('客户端IP: '), true);

      // 断开连接
      client.close();
      
      // 等待断开回调
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(disconnectCount, 1);
    });

    test('WebSocket数据发送和接收', () async {
      String receivedData = '';
      server!.addOnReceiveCallback((data) {
        receivedData = data;
      });

      // 连接WebSocket客户端
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 发送数据
      String testData = 'Hello WebSocket';
      client.add(testData);
      
      // 等待数据接收
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(receivedData, testData);

      client.close();
    });

    test('WebSocket广播功能', () async {
      List<String> receivedMessages = [];
      server!.addOnReceiveCallback((data) {
        receivedMessages.add(data);
      });

      // 连接两个WebSocket客户端
      var client1 = await WebSocket.connect('ws://localhost:$port');
      var client2 = await WebSocket.connect('ws://localhost:$port');
      
      // 等待连接
      await Future.delayed(Duration(milliseconds: 100));
      
      // 通过服务器广播消息
      String broadcastMessage = 'Broadcast test';
      server!.broadcast(broadcastMessage);
      
      // 等待广播消息
      await Future.delayed(Duration(milliseconds: 100));
      
      // 检查客户端是否收到消息
      expect(server!.getClientCount(), 2);

      client1.close();
      client2.close();
    });

    test('WebSocket串口数据转发', () async {
      String receivedData = '';
      server!.addOnReceiveCallback((data) {
        receivedData = data;
      });

      // 通过WebSocket发送真实的串口数据
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 发送实际的串口数据格式
      String serialData = 'UART data: 12345';
      client.add(serialData);
      
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(receivedData, serialData);

      client.close();
    });

    test('WebSocket命令API测试', () async {
      Map<String, dynamic> receivedCommand = {};
      server!.addOnCommandCallback((command) {
        receivedCommand = command;
      });

      // 连接WebSocket客户端
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 发送JSON命令
      Map<String, dynamic> testCommand = {
        'command': 'send_text',
        'data': {
          'message': 'Hello UART via JSON'
        }
      };
      client.add(jsonEncode(testCommand));
      
      // 等待命令接收
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(receivedCommand['command'], testCommand['command']);
      expect(receivedCommand['data']['message'], testCommand['data']['message']);

      client.close();
    });

    test('WebSocket命令解析测试', () async {
      WebSocketCommand? parsedCommand;
      server!.addOnCommandCallback((command) {
        parsedCommand = server!.parseCommand(command['command']);
      });

      // 连接WebSocket客户端
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 发送连接命令
      Map<String, dynamic> connectCommand = {
        'command': 'connect',
        'data': {
          'port': '/dev/ttyUSB0',
          'baudRate': 9600
        }
      };
      client.add(jsonEncode(connectCommand));
      
      // 等待命令接收
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(parsedCommand, WebSocketCommand.connect);

      client.close();
    });

    test('WebSocket响应发送测试', () async {
      String receivedResponse = '';
      int messageCount = 0;
      
      server!.addOnClientConnectCallback((clientInfo) {
        // 发送一个响应来测试
        server!.sendResponse(WebSocketResponseType.systemMessage, {
          'message': 'Test response'
        });
      });

      server!.addOnReceiveCallback((data) {
        receivedResponse = data;
        messageCount++;
      });

      // 连接WebSocket客户端
      var client = await WebSocket.connect('ws://localhost:$port');
      
      // 等待响应
      await Future.delayed(Duration(milliseconds: 150));
      
      client.close();
    });
  });
}
