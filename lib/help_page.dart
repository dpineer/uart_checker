import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({Key? key}) : super(key: key);

  @override
  _HelpPageState createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  AppColors get _colors => AppColors.of(context);

  final Set<int> _expandedSections = {0};

  void _toggleSection(int index) {
    setState(() {
      if (_expandedSections.contains(index)) {
        _expandedSections.remove(index);
      } else {
        _expandedSections.add(index);
      }
    });
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('内容已复制到剪贴板'),
        backgroundColor: _colors.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('说明与使用指南', style: TextStyle(color: _colors.primary)),
        backgroundColor: _colors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: _colors.primary),
            tooltip: '关于',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      body: Container(
        color: _colors.background,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            _buildOverviewSection(),
            SizedBox(height: 12),
            _buildSection(
              index: 1,
              icon: Icons.settings_input_component,
              title: '串口通信',
              subtitle: '多串口连接、收发与监控',
              child: _buildSerialPortGuide(),
            ),
            SizedBox(height: 12),
            _buildSection(
              index: 2,
              icon: Icons.show_chart,
              title: '动态数据图表',
              subtitle: '如何让图表正确显示数据',
              child: _buildChartGuide(),
            ),
            SizedBox(height: 12),
            _buildSection(
              index: 3,
              icon: Icons.network_wifi,
              title: 'WebSocket控制',
              subtitle: '远程控制服务端面板与协议',
              child: _buildWebSocketGuide(),
            ),
            SizedBox(height: 12),
            _buildSection(
              index: 4,
              icon: Icons.terminal,
              title: 'SSH终端',
              subtitle: '远程服务器终端登录',
              child: _buildSshGuide(),
            ),
            SizedBox(height: 12),
            _buildSection(
              index: 5,
              icon: Icons.speed,
              title: '技术指标',
              subtitle: '参数范围、缓冲与性能限制',
              child: _buildSpecsGuide(),
            ),
            SizedBox(height: 12),
            _buildSection(
              index: 6,
              icon: Icons.help_outline,
              title: '常见问题与排障',
              subtitle: '端口、乱码、图表、连接问题',
              child: _buildFaqGuide(),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _colors.surface,
          title: Row(
            children: [
              Icon(Icons.wifi_tethering, color: _colors.primary),
              SizedBox(width: 8),
              Text('通信工具 v1.0.0', style: TextStyle(color: _colors.text)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '基于Flutter的跨平台串口通信调试工具，集成实时数据可视化、WebSocket远程控制与SSH终端功能。',
                style: TextStyle(color: _colors.text),
              ),
              SizedBox(height: 12),
              Text(
                '技术栈：flutter_libserialport / fl_chart / web_socket_channel / dartssh2 + xterm',
                style: TextStyle(color: _colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('确定', style: TextStyle(color: _colors.primary)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverviewSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colors.surface,
        border: Border.all(color: _colors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, color: _colors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                '通信工具总览',
                style: TextStyle(
                  color: _colors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '本工具包含四个功能模块，通过左侧导航栏切换：',
            style: TextStyle(color: _colors.text, fontSize: 13),
          ),
          SizedBox(height: 8),
          _buildFeatureItem(
            Icons.settings_input_component,
            '串口通信',
            '多串口同时连接，实时收发数据，支持文本/HEX模式',
          ),
          SizedBox(height: 6),
          _buildFeatureItem(
            Icons.show_chart,
            '动态数据图表',
            '自动解析 [key:value] 格式数据并绘制实时趋势曲线',
          ),
          SizedBox(height: 6),
          _buildFeatureItem(
            Icons.network_wifi,
            'WebSocket控制',
            '内置WebSocket服务器，支持远程命令控制串口',
          ),
          SizedBox(height: 6),
          _buildFeatureItem(Icons.terminal, 'SSH终端', '内置SSH客户端，可远程登录服务器执行命令'),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _colors.primary, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: _colors.text, fontSize: 13, height: 1.5),
              children: [
                TextSpan(
                  text: '$title：',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _colors.text,
                  ),
                ),
                TextSpan(
                  text: desc,
                  style: TextStyle(color: _colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final bool isExpanded = _expandedSections.contains(index);
    return Container(
      decoration: BoxDecoration(
        color: _colors.surface,
        border: Border.all(
          color: _colors.primary.withOpacity(isExpanded ? 0.8 : 0.4),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleSection(index),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: _colors.primary, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: _colors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildSerialPortGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(
          '1. 连接串口',
          '左侧面板的"串口列表"会自动刷新可用端口（每2秒轮询热插拔）。点击"连接"按钮或使用顶部"连接"按钮（根据"连接目标"模式选择全部/分组/单个），即可建立连接。连接成功后会分配 [编号] 与专属颜色，并在接收区显示。',
        ),
        _buildStepItem(
          '2. 配置参数',
          '连接前可在右侧配置面板设置波特率、数据位、停止位、校验码。配置应用于"新建立的连接"，已连接端口如需变更参数请先断开再重连。',
        ),
        _buildStepItem(
          '3. 发送数据',
          '在底部输入框输入内容，选择发送目标串口后点击"发信"。文本模式下自动追加 \\r\\n 换行；HEX模式下输入十六进制（如 48 65 6C 6C 6F，自动忽略非十六进制字符）。',
        ),
        _buildStepItem(
          '4. 监控模式',
          '"全部监控"显示所有串口数据；"单口监控"仅显示所选串口的数据。接收区顶部的颜色图例对应各串口编号。',
        ),
        _buildStepItem(
          '5. 显示与导出',
          '"复制"复制当前接收区内容；右上角"复制所有显示内容"导出完整会话（含连接信息、收发记录与图表数据）；"清空"重置接收区与图表。时间戳开关控制每行是否显示时间。',
        ),
        _buildNote(
          '被占用的串口（如被其他程序打开）会自动跳过，并在接收区提示；被拔出的串口会自动断开，连接中的串口在重新插入后会自动重连。',
        ),
      ],
    );
  }

  Widget _buildChartGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(
          '1. 开启图表',
          '在右侧配置面板点击"开启图表"，或在WebSocket控制面板中点击"开启图表"按钮。图表区域会提示"等待数据..."。',
        ),
        _buildStepItem(
          '2. 数据格式',
          '图表自动解析串口接收到的 [key:value] 格式数据，一个括号为一组采样点，多个键可同时绘制多组曲线：',
        ),
        _buildCodeBlock('[data:123,BatVoltage:13.24,Demo:2]', copyable: true),
        _buildStepItem(
          '3. 多数据键',
          '每个键自动分配不同颜色并显示在图表标题栏。曲线随数据实时滚动，最多保留 ${100} 个采样点（数据键、颜色可在代码中调整）。',
        ),
        _buildStepItem(
          '4. 读取曲线',
          '横轴为采样序号（数据索引），纵轴为数值。鼠标/手指可上下平移；点击图表右上角可查看图例。多曲线通过颜色区分。',
        ),
        _buildStepItem(
          '5. 常见错误',
          '若图表不显示，请确认：(a) 已开启图表模式；(b) 数据含 [key:value] 格式且value为数值；(c) 键名不能重复冲突。',
        ),
        _buildNote('示例发送内容：发送文本 [data:100]，串口回显相同格式即可看到曲线。HEX模式下图表不解析。'),
      ],
    );
  }

  Widget _buildWebSocketGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(
          '1. 服务器启动',
          '应用启动时自动在端口 9090 启动WebSocket服务器（若被占用会依次尝试 9091、9092...）。"服务端控制面板"显示当前端口、客户端连接数与认证Token。',
        ),
        _buildStepItem(
          '2. 客户端连接',
          '客户端通过 ws://<主机IP>:<端口> 连接。服务器默认开启Token认证，需先发送认证命令再执行其他操作。Token可在控制面板中一键复制。',
        ),
        _buildStepItem('3. 认证命令', '使用 32 位随机Token进行认证：'),
        _buildCodeBlock(
          '{"command":"auth","data":{"token":"<Token>"}}',
          copyable: true,
        ),
        _buildStepItem('4. 控制命令', '认证后可发送以下JSON命令控制串口：'),
        _buildCodeBlock(
          '{"command":"connect","data":{"port":"*","baudRate":9600}}\n'
          '{"command":"disconnect","data":{}}\n'
          '{"command":"list_ports","data":{}}\n'
          '{"command":"send_text","data":{"message":"Hello"}}\n'
          '{"command":"send_hex","data":{"hex":"48656C6C6F"}}\n'
          '{"command":"set_config","data":{"baudRate":115200}}\n'
          '{"command":"set_hex_mode","data":{"enabled":true}}\n'
          '{"command":"set_chart_mode","data":{"enabled":true}}',
          copyable: true,
        ),
        _buildStepItem(
          '5. 数据转发',
          '串口接收的数据会实时广播给所有已认证客户端（文本以 "端口号" 前缀标识）。客户端也可向服务器发送原始文本（非JSON），服务器会将其转发到所有已连接串口。',
        ),
        _buildStepItem(
          '6. 服务端面板',
          '"WebSocket控制"页面的日志区记录所有客户端连接/断开与命令执行情况，可直接在页面内发送文本/HEX到串口。',
        ),
        _buildNote(
          '所有响应格式为 {"type":"类型","data":{...}}，类型包括 command_response / error / port_status / serial_data。',
        ),
      ],
    );
  }

  Widget _buildSshGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(
          '1. 填写连接信息',
          '在顶部配置栏填写主机IP、端口（默认22）、用户名与密码。连接后输入框自动锁定，防止误改。',
        ),
        _buildStepItem(
          '2. 建立连接',
          '点击"连接"按钮，应用通过SSH建立会话并分配伪终端(PTY)。连接成功右上角显示绿色"已连接"状态，终端区域可正常交互。',
        ),
        _buildStepItem('3. 使用终端', '终端支持ANSI颜色、方向键、Tab补全等交互。窗口大小变化时自动同步PTY尺寸。'),
        _buildStepItem(
          '4. 断开连接',
          '点击"断开"按钮或直接退出远程会话（如输入 exit）。网络异常或服务端关闭会话时终端自动提示断开。',
        ),
        _buildNote('密码以明文存储于输入框中，请勿在不可信环境中使用；当前实现不保存历史连接记录。'),
      ],
    );
  }

  Widget _buildSpecsGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpecRow('支持的波特率', '4800 / 9600 / 19200 / 38400 / 57600 / 115200'),
        _buildSpecRow('数据位', '5 / 6 / 7 / 8 位'),
        _buildSpecRow('停止位', '1 / 1.5 / 2 位'),
        _buildSpecRow('校验方式', '无校验 / 奇校验 / 偶校验 / 标记 / 空格'),
        _buildSpecRow('数据编码识别', 'UTF-8 → ASCII → Latin1 自动尝试，失败回退为HEX'),
        _buildSpecRow('HEX模式', '接收与发送均按字节显示，空格分隔两位十六进制'),
        _buildSpecRow('数据包重组', '50ms 超时合并粘包，缓冲上限 1024 字节'),
        _buildSpecRow('显示行数上限', '最多保留 1000 行，自动裁剪防止内存溢出'),
        _buildSpecRow('图表采样点', '每数据键最多 100 个点，曲线窗口滚动显示'),
        _buildSpecRow('WebSocket端口', '默认 9090，被占用时自动顺延（最多尝试10次）'),
        _buildSpecRow('WebSocket认证', '32位随机Token，连接后须先认证'),
        _buildSpecRow('SSH端口', '默认22，可自定义'),
        _buildSpecRow('串口轮询', '每 2 秒检测可用端口变化，支持热插拔'),
        _buildSpecRow('连接模式', '全部 / 分组 / 单个'),
        _buildSpecRow('监控模式', '全部监控 / 单口监控'),
        SizedBox(height: 8),
        _buildNote(
          '性能说明：接收数据经过智能文本校验（过滤乱码）、HEX高亮、时间戳处理后在1000行内滚动显示；图表仅绘制 [key:value] 数值数据，避免大流量文本导致界面卡顿。',
        ),
      ],
    );
  }

  Widget _buildFaqGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(
          '端口无法识别',
          '检查设备驱动是否安装、USB调试权限是否开启；Linux下需确保当前用户有 /dev/tty* 读写权限（可加入 dialout 组）。',
        ),
        _buildStepItem(
          '数据乱码',
          '确认两端波特率、数据位、停止位、校验位完全一致；若设备发送二进制数据，请切换HEX模式查看原始字节。',
        ),
        _buildStepItem(
          '图表不显示',
          '确认已开启图表模式，且数据严格符合 [key:value] 格式（value必须为数字），键名与已有键不冲突。',
        ),
        _buildStepItem(
          'WebSocket连接失败',
          '确认应用已启动且服务端面板显示端口号；检查防火墙是否放行该端口；确认使用了正确的Token认证。',
        ),
        _buildStepItem(
          '串口被占用',
          '关闭其他占用该串口的程序（如minicom、设备厂商工具），或使用"被占用自动跳过"功能仅连接空闲端口。',
        ),
        _buildStepItem('发送失败', '确认已选择发送目标串口且该串口处于已连接状态；HEX模式下输入必须为有效十六进制字符。'),
      ],
    );
  }

  Widget _buildStepItem(String title, String content) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _colors.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 3),
          Text(
            content,
            style: TextStyle(color: _colors.text, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(String content) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _colors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colors.primary.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _colors.primary, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              content,
              style: TextStyle(color: _colors.text, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String code, {bool copyable = false}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _colors.hexBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: TextStyle(
                color: _colors.text,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
          if (copyable)
            InkWell(
              onTap: () => _copyText(code),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: _colors.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: _colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: _colors.text,
                  fontSize: 13,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: '$label：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(color: _colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
