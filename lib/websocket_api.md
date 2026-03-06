# WebSocket API 文档

## 概述

WebSocket服务器提供了一套完整的API来远程控制串口通信。通过WebSocket连接，客户端可以发送命令来控制串口的连接、数据发送、配置更改等操作。

## 连接信息

- **默认端口**: 8080
- **协议**: WebSocket (ws://)
- **地址示例**: ws://localhost:8080

## 认证机制

所有客户端在执行任何命令之前必须先进行认证。认证使用token验证机制，客户端需要发送认证命令并提供有效的token才能获得访问权限。

## 命令格式

所有命令都使用JSON格式发送：

```json
{
  "command": "command_name",
  "data": {
    // 命令特定的数据
  }
}
```

## 支持的命令

### 0. 认证命令 (新)
- **命令**: `auth`
- **描述**: 客户端认证，验证token以获得访问权限
- **数据格式**:
```json
{
  "command": "auth",
  "data": {
    "token": "your_auth_token_here"
  }
}
```

### 1. 连接串口
- **命令**: `connect`
- **描述**: 连接到指定的串口
- **数据格式**:
```json
{
  "command": "connect",
  "data": {
    "port": "/dev/ttyUSB0",
    "baudRate": 9600,
    "dataBits": 8,
    "stopBits": 1,
    "parity": "none"
  }
}
```

### 2. 断开串口
- **命令**: `disconnect`
- **描述**: 断开当前串口连接
- **数据格式**:
```json
{
  "command": "disconnect",
  "data": {}
}
```

### 3. 列出可用串口
- **命令**: `list_ports`
- **描述**: 获取系统中所有可用的串口列表
- **数据格式**:
```json
{
  "command": "list_ports",
  "data": {}
}
```

### 4. 发送文本数据
- **命令**: `send_text`
- **描述**: 向串口发送文本数据
- **数据格式**:
```json
{
  "command": "send_text",
  "data": {
    "message": "Hello UART"
  }
}
```

### 5. 发送HEX数据
- **命令**: `send_hex`
- **描述**: 向串口发送HEX格式数据
- **数据格式**:
```json
{
  "command": "send_hex",
  "data": {
    "hex": "48656C6C6F"  // "Hello"的HEX表示
  }
}
```

### 6. 设置串口配置
- **命令**: `set_config`
- **描述**: 更改串口配置参数
- **数据格式**:
```json
{
  "command": "set_config",
  "data": {
    "baudRate": 115200,
    "dataBits": 8,
    "stopBits": 1,
    "parity": "none"
  }
}
```

### 7. 设置HEX模式
- **命令**: `set_hex_mode`
- **描述**: 启用或禁用HEX显示模式
- **数据格式**:
```json
{
  "command": "set_hex_mode",
  "data": {
    "enabled": true
  }
}
```

### 8. 设置图表模式
- **命令**: `set_chart_mode`
- **描述**: 启用或禁用数据图表显示
- **数据格式**:
```json
{
  "command": "set_chart_mode",
  "data": {
    "enabled": true
  }
}
```

## 响应格式

服务器会发送以下格式的响应：

```json
{
  "type": "response_type",
  "data": {
    // 响应数据
  },
  "timestamp": "2023-12-07T10:30:00.000"
}
```

### 响应类型

- `command_response`: 命令执行结果
- `serial_data`: 串口接收到的数据
- `system_message`: 系统消息
- `port_status`: 串口状态信息
- `error`: 错误信息

## 状态信息

### 端口状态响应
```json
{
  "type": "port_status",
  "data": {
    "connected": true,
    "port": "/dev/ttyUSB0",
    "baudRate": 9600,
    "hexMode": false,
    "chartMode": true
  },
  "timestamp": "2023-12-07T10:30:00.000"
}
```

### 错误响应
```json
{
  "type": "error",
  "data": {
    "command": "connect",
    "error": "串口未指定",
    "code": 4002
  },
  "timestamp": "2023-12-07T10:30:00.000"
}
```

## 客户端示例

### JavaScript客户端示例

```javascript
// 连接到WebSocket服务器
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = function(event) {
  console.log('已连接到WebSocket服务器');
  
  // 发送连接串口命令
  const connectCmd = {
    command: 'connect',
    data: {
      port: '/dev/ttyUSB0',
      baudRate: 9600
    }
  };
  ws.send(JSON.stringify(connectCmd));
};

ws.onmessage = function(event) {
  const response = JSON.parse(event.data);
  console.log('收到响应:', response);
  
  if (response.type === 'serial_data') {
    console.log('串口数据:', response.data);
  }
};

ws.onclose = function(event) {
  console.log('WebSocket连接已关闭');
};

// 发送文本数据
function sendText(text) {
  const sendCmd = {
    command: 'send_text',
    data: {
      message: text
    }
  };
  ws.send(JSON.stringify(sendCmd));
}

// 发送HEX数据
function sendHex(hex) {
  const sendCmd = {
    command: 'send_hex',
    data: {
      hex: hex
    }
  };
  ws.send(JSON.stringify(sendCmd));
}
```

## 错误代码

- `4001`: 未知命令
- `4002`: 串口未指定
- `4003`: 串口未连接
- `4004`: 数据发送不完整
- `4005`: 发送失败
- `4006`: 无效的HEX数据
- `4007`: 需要先进行认证
- `4008`: 认证失败

## 向后兼容性

为了保持向后兼容性，服务器仍然支持直接发送原始数据（非JSON格式），这些数据将被视为`raw_data`命令进行处理。