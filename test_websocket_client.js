const WebSocket = require('ws');

// 从命令行参数获取服务器地址和认证token
const serverUrl = process.argv[2] || 'ws://localhost:9091';
const authToken = process.argv[3]; // 如果没有提供token，则需要先连接后认证

console.log(`尝试连接到: ${serverUrl}`);
console.log(`认证Token: ${authToken ? authToken : '未提供'}`);

// 连接到WebSocket服务器
const ws = new WebSocket(serverUrl);

// 认证状态
let isAuthenticated = false;

ws.on('open', function open() {
  console.log('已连接到WebSocket服务器');
  
  // 如果提供了token，立即进行认证
  if (authToken) {
    console.log('使用提供的Token进行认证...');
    ws.send(JSON.stringify({
      command: 'auth',
      data: {
        token: authToken
      }
    }));
  } else {
    console.log('未提供Token，需要先获取认证Token');
    console.log('请在应用界面查看WebSocket认证Token，或通过其他方式获取');
  }
});

ws.on('message', function message(data) {
  const messageStr = data.toString();
  console.log('收到服务器消息:', messageStr);
  
  try {
    const response = JSON.parse(messageStr);
    
    // 检查认证响应
    if (response.type === 'command_response' && response.data.command === 'auth') {
      if (response.data.success) {
        console.log('认证成功！');
        isAuthenticated = true;
        
        // 认证成功后发送测试命令
        sendTestCommands();
      } else {
        console.log('认证失败:', response.data.message || '未知错误');
        isAuthenticated = false;
      }
    }
    
    // 检查未认证错误
    if (response.type === 'error' && response.data.code === 4007) {
      console.log('错误: 需要先进行认证');
      isAuthenticated = false;
    }
  } catch (e) {
    // 如果不是JSON格式的消息，忽略
  }
});

ws.on('close', function close() {
  console.log('WebSocket连接已关闭');
});

ws.on('error', function error(err) {
  console.log('WebSocket错误:', err);
});

// 发送测试命令的函数
function sendTestCommands() {
  if (!isAuthenticated) {
    console.log('错误: 需要先进行认证才能发送命令');
    return;
  }
  
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
}

// 如果连接后没有提供token，可以手动发送认证命令
setTimeout(() => {
  if (!isAuthenticated && authToken) {
    console.log('尝试重新发送认证...');
    ws.send(JSON.stringify({
      command: 'auth',
      data: {
        token: authToken
      }
    }));
  }
}, 5000);
