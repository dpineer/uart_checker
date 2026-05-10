import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

/// SSH 终端视图与控制逻辑
/// 依赖: dartssh2, xterm
/// 功能: 提供SSH连接配置、密码鉴权、伪终端(PTY)分配及ANSI颜色流渲染
class SshTerminalPage extends StatefulWidget {
  @override
  _SshTerminalPageState createState() => _SshTerminalPageState();
}

class _SshTerminalPageState extends State<SshTerminalPage> {
  static const Color vsCodeBackground = Color(0xFF1E1E1E);
  static const Color vsCodeSurface = Color(0xFF252526);
  static const Color vsCodeBlue = Color(0xFF569CD6);
  static const Color vsCodeText = Color(0xFFD4D4D4);
  static const Color vsCodeTextSecondary = Color(0xFF858585);

  final TextEditingController _hostCtrl = TextEditingController(text: '127.0.0.1');
  final TextEditingController _portCtrl = TextEditingController(text: '22');
  final TextEditingController _userCtrl = TextEditingController(text: 'root');
  final TextEditingController _passCtrl = TextEditingController();

  final Terminal _terminal = Terminal();
  SSHClient? _sshClient;
  SSHSession? _sshSession;
  StreamSubscription<String>? _stdoutSubscription;

  bool _isConnecting = false;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (String data) {
      if (_isConnected && _sshSession != null) {
        _sshSession!.write(utf8.encode(data));
      }
    };
    _terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      if (_isConnected && _sshSession != null) {
        _sshSession!.resizeTerminal(width, height);
      }
    };
  }

  @override
  void dispose() {
    _disconnect();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (host.isEmpty || username.isEmpty) {
      _showMsg('主机和用户名不能为空');
      return;
    }

    setState(() {
      _isConnecting = true;
      _terminal.eraseDisplay();
      _terminal.write('Connecting to $username@$host:$port...\r\n');
    });

    try {
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 5));

      _sshClient = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      _sshSession = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      _stdoutSubscription = _sshSession!.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen((data) {
        _terminal.write(data);
      }, onDone: () {
        _handleDisconnect();
      }, onError: (e) {
        _terminal.write('\r\n[SSH Error]: $e\r\n');
        _handleDisconnect();
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      _terminal.write('\r\n[Connection Failed]: $e\r\n');
      _showMsg('连接失败: $e');
    }
  }

  void _disconnect() {
    _stdoutSubscription?.cancel();
    _sshSession?.close();
    _sshClient?.close();
    _handleDisconnect();
  }

  void _handleDisconnect() {
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
      });
    }
    _terminal.write('\r\n[Disconnected from host]\r\n');
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: vsCodeBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: vsCodeBackground,
      appBar: AppBar(
        title: Text('SSH 远程终端', style: TextStyle(color: vsCodeBlue)),
        backgroundColor: vsCodeBackground,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.all(8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _isConnected ? '已连接' : '未连接',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ========== 顶部配置栏 ==========
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: vsCodeBlue.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Expanded(child: _buildInput('主机 (IP)', _hostCtrl, enabled: !_isConnected)),
                SizedBox(width: 8),
                SizedBox(width: 80, child: _buildInput('端口', _portCtrl, enabled: !_isConnected)),
                SizedBox(width: 8),
                Expanded(child: _buildInput('用户', _userCtrl, enabled: !_isConnected)),
                SizedBox(width: 8),
                Expanded(child: _buildInput('密码', _passCtrl, obscureText: true, enabled: !_isConnected)),
                SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isConnecting ? null : (_isConnected ? _disconnect : _connect),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : vsCodeBlue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  icon: _isConnecting
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_isConnected ? Icons.stop : Icons.play_arrow, size: 18),
                  label: Text(_isConnected ? '断开' : '连接'),
                )
              ],
            ),
          ),

          // ========== xterm 渲染区域 ==========
          Expanded(
            child: Container(
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: vsCodeBlue.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                  child: TerminalView(
                    _terminal,
                    textStyle: TerminalStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {bool obscureText = false, bool enabled = true}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      style: TextStyle(color: vsCodeText, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: vsCodeTextSecondary, fontSize: 12),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeTextSecondary.withOpacity(0.5))),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeBlue)),
        disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: vsCodeSurface)),
      ),
    );
  }
}