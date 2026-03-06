const WebSocket = require('ws');

// 连接到WebSocket服务器
const ws = new WebSocket('ws://localhost:9091');

ws.on('open', function open() {
  console.log('已连接到WebSocket服务器');

  // 测试发送命令
  console.log('发送测试命令...');
  
  // 1. 发送列出端口命令
  ws.send(JSON.stringify({
    command: 'list_ports',
    data: {}
  }));

  // 2. 发送设置HEX模式命令
  ws.send(JSON.stringify({
    command: 'set_hex_mode',
    data: {
      enabled: false
    }
  }));

  // 3. 发送文本数据命令
  setTimeout(() => {
    ws.send(JSON.stringify({
      command: 'send_text',
      data: {
        message: 'Hello from WebSocket client!'
      }
    }));
  }, 1000);

  // 4. 发送设置图表模式命令
  setTimeout(() => {
    ws.send(JSON.stringify({
      command: 'set_chart_mode',
      data: {
        enabled: true
      }
    }));
  }, 2000);
});

ws.on('message', function message(data) {
  console.log('收到服务器消息:', data.toString());
});

ws.on('close', function close() {
  console.log('WebSocket连接已关闭');
});

ws.on('error', function error(err) {
  console.log('WebSocket错误:', err);
});