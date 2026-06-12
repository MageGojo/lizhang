import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'models/import_models.dart';
import 'models/ledger_entry.dart';
import 'services/ledger_controller.dart';
import 'services/ledger_database.dart';
import 'services/money.dart';

const _expenseShortcuts = [
  _QuickCategory('餐饮', Icons.restaurant_rounded, Color(0xFFE45D4C)),
  _QuickCategory('交通', Icons.directions_transit_rounded, Color(0xFF2563EB)),
  _QuickCategory('购物', Icons.shopping_bag_rounded, Color(0xFFC2417D)),
  _QuickCategory('房租', Icons.home_rounded, Color(0xFF0F766E)),
  _QuickCategory('医疗', Icons.local_hospital_rounded, Color(0xFFDC2626)),
  _QuickCategory('娱乐', Icons.movie_rounded, Color(0xFFB45309)),
];

const _incomeShortcuts = [
  _QuickCategory('工资', Icons.payments_rounded, Color(0xFF0F9F6E)),
  _QuickCategory('奖金', Icons.card_giftcard_rounded, Color(0xFFD97706)),
  _QuickCategory('报销', Icons.assignment_return_rounded, Color(0xFF2563EB)),
  _QuickCategory('理财', Icons.savings_rounded, Color(0xFF0F766E)),
];

final _quickCategoryLabels = {
  for (final item in [..._expenseShortcuts, ..._incomeShortcuts]) item.label,
};

class _QuickCategory {
  const _QuickCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class _EntryVisual {
  const _EntryVisual({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LedgerDatabase.configureDatabaseFactory();
  runApp(LizhangApp(controller: LedgerController(LedgerDatabase())));
}

class LizhangApp extends StatelessWidget {
  const LizhangApp({super.key, required this.controller});

  final LedgerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '璃账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamilyFallback: const [
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'Arial',
        ],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF14B8A6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F8F7),
      ),
      home: LedgerHome(controller: controller),
    );
  }
}

class LedgerHome extends StatefulWidget {
  const LedgerHome({super.key, required this.controller});

  final LedgerController controller;

  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  final _anchorController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController(text: '餐饮');
  final _merchantController = TextEditingController();
  final _noteController = TextEditingController();
  final _pasteController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription<List<SharedMediaFile>>? _mediaSub;
  EntryType _type = EntryType.expense;
  DateTime _occurredAt = DateTime.now();
  LedgerEntry? _editing;

  LedgerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.load();
    _setupShareReceivers();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    _anchorController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    _merchantController.dispose();
    _noteController.dispose();
    _pasteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupShareReceivers() {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      for (final file in files) {
        _handleSharedMedia(file);
      }
    });
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (!mounted) {
        return;
      }
      for (final file in files) {
        _handleSharedMedia(file);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return Scaffold(
          body: LiquidBackground(
            child: SafeArea(
              child: snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1160;
                        final content = wide
                            ? _buildWideLayout(snapshot)
                            : _buildCompactLayout(snapshot);
                        return Scrollbar(
                          controller: _scrollController,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              wide ? 28 : 16,
                              _desktopTopPadding(),
                              wide ? 28 : 16,
                              24,
                            ),
                            child: content,
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout(LedgerSnapshot snapshot) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 350,
          child: Column(
            children: [
              _BalancePanel(
                snapshot: snapshot,
                anchorController: _anchorController,
                onSaveAnchor: _saveAnchor,
              ),
              const SizedBox(height: 16),
              _ImportPanel(
                preview: controller.preview,
                isBusy: controller.isBusy,
                onPickFile: _pickFile,
                onPaste: _showPasteDialog,
                onApply: _applyPreview,
                onCancel: controller.clearPreview,
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              _EntryEditor(
                type: _type,
                editing: _editing,
                amountController: _amountController,
                categoryController: _categoryController,
                merchantController: _merchantController,
                noteController: _noteController,
                occurredAt: _occurredAt,
                onTypeChanged: _changeEntryType,
                onPickDate: _pickEntryDate,
                onSave: _saveEntry,
                onCancelEdit: _resetEditor,
              ),
              const SizedBox(height: 16),
              _EntryListPanel(
                title: '今日流水',
                entries: snapshot.todayEntries.isEmpty
                    ? snapshot.entries.take(6).toList()
                    : snapshot.todayEntries,
                onEdit: _startEdit,
                onDelete: _deleteEntry,
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 380,
          child: _ArchivePanel(
            archives: snapshot.archives,
            onEdit: _startEdit,
            onDelete: _deleteEntry,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(LedgerSnapshot snapshot) {
    return Column(
      children: [
        _BalancePanel(
          snapshot: snapshot,
          anchorController: _anchorController,
          onSaveAnchor: _saveAnchor,
        ),
        const SizedBox(height: 14),
        _EntryEditor(
          type: _type,
          editing: _editing,
          amountController: _amountController,
          categoryController: _categoryController,
          merchantController: _merchantController,
          noteController: _noteController,
          occurredAt: _occurredAt,
          onTypeChanged: _changeEntryType,
          onPickDate: _pickEntryDate,
          onSave: _saveEntry,
          onCancelEdit: _resetEditor,
        ),
        const SizedBox(height: 14),
        _ImportPanel(
          preview: controller.preview,
          isBusy: controller.isBusy,
          onPickFile: _pickFile,
          onPaste: _showPasteDialog,
          onApply: _applyPreview,
          onCancel: controller.clearPreview,
        ),
        const SizedBox(height: 14),
        _EntryListPanel(
          title: '今日流水',
          entries: snapshot.todayEntries.isEmpty
              ? snapshot.entries.take(6).toList()
              : snapshot.todayEntries,
          onEdit: _startEdit,
          onDelete: _deleteEntry,
        ),
        const SizedBox(height: 14),
        _ArchivePanel(
          archives: snapshot.archives,
          onEdit: _startEdit,
          onDelete: _deleteEntry,
        ),
      ],
    );
  }

  double _desktopTopPadding() {
    if (kIsWeb) {
      return 20;
    }
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux ? 64 : 20;
  }

  Future<void> _saveAnchor() async {
    try {
      await controller.setBalanceAnchor(_anchorController.text);
      _anchorController.clear();
      _showSnack('当前金额已更新');
    } on FormatException catch (error) {
      _showSnack(error.message);
    } catch (error) {
      _showSnack('当前金额保存失败：$error');
    }
  }

  Future<void> _saveEntry() async {
    final wasEditing = _editing != null;
    try {
      await controller.saveEntry(
        id: _editing?.id,
        type: _type,
        amountText: _amountController.text,
        occurredAt: _occurredAt,
        category: _categoryController.text,
        merchant: _merchantController.text,
        note: _noteController.text,
      );
      _resetEditor();
      _showSnack(wasEditing ? '已更新账目' : '已记一笔');
    } on FormatException catch (error) {
      _showSnack(error.message);
    } catch (error) {
      _showSnack('保存账目失败：$error');
    }
  }

  void _changeEntryType(EntryType value) {
    setState(() {
      _type = value;
      final category = _categoryController.text.trim();
      if (category.isEmpty || _quickCategoryLabels.contains(category)) {
        _categoryController.text = value == EntryType.income ? '工资' : '餐饮';
      }
    });
  }

  void _resetEditor() {
    setState(() {
      _editing = null;
      _type = EntryType.expense;
      _occurredAt = DateTime.now();
      _amountController.clear();
      _categoryController.text = '餐饮';
      _merchantController.clear();
      _noteController.clear();
    });
  }

  void _startEdit(LedgerEntry entry) {
    setState(() {
      _editing = entry;
      _type = entry.type;
      _occurredAt = entry.occurredAt;
      _amountController.text = formatPlainMoney(entry.amountCents);
      _categoryController.text = entry.category;
      _merchantController.text = entry.merchant;
      _noteController.text = entry.note;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _deleteEntry(LedgerEntry entry) async {
    if (entry.id == null) {
      return;
    }
    try {
      await controller.deleteEntry(entry.id!);
    } catch (error) {
      _showSnack('删除失败：$error');
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除账目'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => controller.restoreEntry(entry.id!),
        ),
      ),
    );
  }

  Future<void> _pickEntryDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) {
      return;
    }
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _occurredAt.hour,
        _occurredAt.minute,
      );
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls', 'txt'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    await _previewPath(path, ImportMethod.file);
  }

  Future<void> _previewPath(String path, ImportMethod method) async {
    try {
      await controller.previewFile(path, method);
      _showSnack('导入预览已生成');
    } catch (error) {
      _showSnack('导入失败：$error');
    }
  }

  void _handleSharedMedia(SharedMediaFile file) {
    if (file.path.trim().isEmpty) {
      return;
    }
    if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
      _previewText(file.path);
      return;
    }
    _previewPath(file.path, ImportMethod.share);
  }

  Future<void> _previewText(String text) async {
    try {
      await controller.previewText(text);
      _showSnack('粘贴账单已解析');
    } catch (error) {
      _showSnack('解析失败：$error');
    }
  }

  Future<void> _showPasteDialog() async {
    _pasteController.clear();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴账单'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: _pasteController,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                hintText: '粘贴微信或支付宝账单表格文本',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _pasteController.text),
              child: const Text('生成预览'),
            ),
          ],
        );
      },
    );
    if (text != null && text.trim().isNotEmpty) {
      await _previewText(text);
    }
  }

  Future<void> _applyPreview() async {
    try {
      final inserted = await controller.applyPreview();
      _showSnack('已导入 $inserted 笔');
    } catch (error) {
      _showSnack('导入保存失败：$error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7FBFA),
                  Color(0xFFE8F6F1),
                  Color(0xFFF9FAF8),
                ],
              ),
            ),
            child: CustomPaint(painter: _LiquidMeshPainter()),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _LiquidMeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x1F0F766E);
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.12 + i * 0.13);
      final path = Path()..moveTo(0, y);
      path.cubicTo(
        size.width * 0.25,
        y - 36,
        size.width * 0.62,
        y + 42,
        size.width,
        y - 10,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({
    required this.snapshot,
    required this.anchorController,
    required this.onSaveAnchor,
  });

  final LedgerSnapshot snapshot;
  final TextEditingController anchorController;
  final VoidCallback onSaveAnchor;

  @override
  Widget build(BuildContext context) {
    final anchorTime = DateFormat('MM-dd HH:mm').format(snapshot.anchor.asOf);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '璃账',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('本地账本', style: TextStyle(color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const _TinyChip(label: 'AI 数字分析'),
            ],
          ),
          const SizedBox(height: 24),
          const Text('实时余额', style: TextStyle(color: Color(0xFF64748B))),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(snapshot.realtimeBalanceCents),
              style: const TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: '收入',
                  value: formatMoney(snapshot.totalIncomeCents),
                  color: const Color(0xFF0F9F6E),
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: '支出',
                  value: formatMoney(snapshot.totalExpenseCents),
                  color: const Color(0xFFE05252),
                  icon: Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: anchorController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '当前金额',
              helperText: '锚点：$anchorTime',
              prefixIcon: const Icon(Icons.savings_rounded),
              prefixText: '¥ ',
              suffixIcon: IconButton(
                tooltip: '校准余额',
                onPressed: onSaveAnchor,
                icon: const Icon(Icons.check_circle_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onSubmitted: (_) => onSaveAnchor(),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFCF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC6F4E7)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F766E),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

_EntryVisual _visualForEntry(LedgerEntry entry) {
  return _visualForCategory(
    entry.category,
    entry.type,
    merchant: entry.merchant,
    note: entry.note,
  );
}

_EntryVisual _visualForCategory(
  String category,
  EntryType type, {
  String merchant = '',
  String note = '',
}) {
  final text = '$category $merchant $note'.toLowerCase();
  bool hasAny(List<String> keywords) {
    return keywords.any(text.contains);
  }

  if (type == EntryType.income) {
    if (hasAny(['工资', '薪', 'salary', '奖金', 'bonus'])) {
      return const _EntryVisual(
        icon: Icons.payments_rounded,
        color: Color(0xFF0F9F6E),
        label: '工资',
      );
    }
    if (hasAny(['报销', '退款', '返现', 'refund'])) {
      return const _EntryVisual(
        icon: Icons.assignment_return_rounded,
        color: Color(0xFF2563EB),
        label: '报销',
      );
    }
    if (hasAny(['理财', '利息', '分红', '基金', '股票'])) {
      return const _EntryVisual(
        icon: Icons.savings_rounded,
        color: Color(0xFF0F766E),
        label: '理财',
      );
    }
    return const _EntryVisual(
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFF0F9F6E),
      label: '收入',
    );
  }

  if (hasAny(['餐', '饭', '咖啡', '奶茶', '早餐', '午餐', '晚餐', '外卖', '食'])) {
    return const _EntryVisual(
      icon: Icons.restaurant_rounded,
      color: Color(0xFFE45D4C),
      label: '餐饮',
    );
  }
  if (hasAny(['交通', '公交', '地铁', '打车', '滴滴', '高铁', '火车', '停车'])) {
    return const _EntryVisual(
      icon: Icons.directions_transit_rounded,
      color: Color(0xFF2563EB),
      label: '交通',
    );
  }
  if (hasAny(['购物', '超市', '淘宝', '京东', '拼多多', '商场', '衣', '鞋'])) {
    return const _EntryVisual(
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFFC2417D),
      label: '购物',
    );
  }
  if (hasAny(['房', '租', '物业', '水电', '燃气', '电费', '水费'])) {
    return const _EntryVisual(
      icon: Icons.home_rounded,
      color: Color(0xFF0F766E),
      label: '居住',
    );
  }
  if (hasAny(['医疗', '药', '医院', '门诊', '体检'])) {
    return const _EntryVisual(
      icon: Icons.local_hospital_rounded,
      color: Color(0xFFDC2626),
      label: '医疗',
    );
  }
  if (hasAny(['娱乐', '电影', '游戏', '会员', '演出', '音乐'])) {
    return const _EntryVisual(
      icon: Icons.movie_rounded,
      color: Color(0xFFB45309),
      label: '娱乐',
    );
  }
  if (hasAny(['学习', '书', '课程', '教育', '培训'])) {
    return const _EntryVisual(
      icon: Icons.school_rounded,
      color: Color(0xFF4F46E5),
      label: '学习',
    );
  }
  if (hasAny(['旅行', '酒店', '机票', '旅游', '航班'])) {
    return const _EntryVisual(
      icon: Icons.flight_takeoff_rounded,
      color: Color(0xFF0284C7),
      label: '旅行',
    );
  }
  if (hasAny(['转账', '还款', '借款', '信用卡'])) {
    return const _EntryVisual(
      icon: Icons.swap_horiz_rounded,
      color: Color(0xFF475569),
      label: '转账',
    );
  }
  if (hasAny(['话费', '手机', '流量', '宽带'])) {
    return const _EntryVisual(
      icon: Icons.phone_iphone_rounded,
      color: Color(0xFF0891B2),
      label: '通讯',
    );
  }
  return const _EntryVisual(
    icon: Icons.receipt_long_rounded,
    color: Color(0xFFE05252),
    label: '支出',
  );
}

String _sourceLabel(String source) {
  switch (source.toLowerCase()) {
    case 'manual':
      return '手动';
    case 'wechat':
      return '微信';
    case 'alipay':
      return '支付宝';
    default:
      return source.trim().isEmpty ? '账单' : source;
  }
}

IconData _sourceIcon(String source) {
  switch (source.toLowerCase()) {
    case 'wechat':
      return Icons.chat_bubble_rounded;
    case 'alipay':
      return Icons.account_balance_wallet_rounded;
    case 'manual':
      return Icons.edit_note_rounded;
    default:
      return Icons.description_rounded;
  }
}

Color _sourceColor(String source) {
  switch (source.toLowerCase()) {
    case 'wechat':
      return const Color(0xFF10B981);
    case 'alipay':
      return const Color(0xFF1677FF);
    case 'manual':
      return const Color(0xFF64748B);
    default:
      return const Color(0xFF0F766E);
  }
}

bool _isImportedSource(String source) {
  return source.toLowerCase() != 'manual';
}

class _EntryEditor extends StatelessWidget {
  const _EntryEditor({
    required this.type,
    required this.editing,
    required this.amountController,
    required this.categoryController,
    required this.merchantController,
    required this.noteController,
    required this.occurredAt,
    required this.onTypeChanged,
    required this.onPickDate,
    required this.onSave,
    required this.onCancelEdit,
  });

  final EntryType type;
  final LedgerEntry? editing;
  final TextEditingController amountController;
  final TextEditingController categoryController;
  final TextEditingController merchantController;
  final TextEditingController noteController;
  final DateTime occurredAt;
  final ValueChanged<EntryType> onTypeChanged;
  final VoidCallback onPickDate;
  final VoidCallback onSave;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final shortcuts = type == EntryType.income
        ? _incomeShortcuts
        : _expenseShortcuts;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  editing == null ? '记一笔' : '修改账目',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SegmentedButton<EntryType>(
                segments: const [
                  ButtonSegment(
                    value: EntryType.expense,
                    label: Text('支出'),
                    icon: Icon(Icons.trending_down_rounded),
                  ),
                  ButtonSegment(
                    value: EntryType.income,
                    label: Text('收入'),
                    icon: Icon(Icons.trending_up_rounded),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (values) => onTypeChanged(values.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: categoryController,
            builder: (context, value, _) {
              final selected = value.text.trim();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: shortcuts.map((shortcut) {
                  return _CategoryShortcutButton(
                    shortcut: shortcut,
                    selected: selected == shortcut.label,
                    onTap: () => categoryController.text = shortcut.label,
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 170,
                child: TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '金额',
                    prefixIcon: Icon(Icons.payments_rounded),
                    prefixText: '¥ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: '分类',
                    prefixIcon: Icon(Icons.category_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: merchantController,
                  decoration: const InputDecoration(
                    labelText: '商户/对象',
                    prefixIcon: Icon(Icons.storefront_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 210,
                child: OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(DateFormat('yyyy-MM-dd').format(occurredAt)),
                  style: OutlinedButton.styleFrom(
                    fixedSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: '备注',
              prefixIcon: Icon(Icons.notes_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onSave,
                icon: Icon(
                  editing == null ? Icons.add_rounded : Icons.save_rounded,
                ),
                label: Text(editing == null ? '保存' : '更新'),
              ),
              if (editing != null) ...[
                const SizedBox(width: 10),
                TextButton(onPressed: onCancelEdit, child: const Text('取消修改')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryShortcutButton extends StatelessWidget {
  const _CategoryShortcutButton({
    required this.shortcut,
    required this.selected,
    required this.onTap,
  });

  final _QuickCategory shortcut;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : shortcut.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? shortcut.color
              : shortcut.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? shortcut.color.withValues(alpha: 0.42)
                : shortcut.color.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shortcut.icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              shortcut.label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.preview,
    required this.isBusy,
    required this.onPickFile,
    required this.onPaste,
    required this.onApply,
    required this.onCancel,
  });

  final ImportPreview? preview;
  final bool isBusy;
  final VoidCallback onPickFile;
  final VoidCallback onPaste;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final current = preview;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.move_to_inbox_rounded,
                  color: Color(0xFF0F766E),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '导入中心',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onPickFile,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('选择文件'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPaste,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: const Text('粘贴账单'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '微信 / 支付宝 CSV、XLSX、文本',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
          if (current != null) ...[
            const SizedBox(height: 14),
            _PreviewSummary(preview: current),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: current.candidates.take(30).length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final candidate = current.candidates[index];
                  return _PreviewRow(candidate: candidate);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: current.hasImportableRows ? onApply : null,
                    icon: const Icon(Icons.playlist_add_check_rounded),
                    label: Text('确认导入 ${current.validCount} 笔'),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: onCancel, child: const Text('取消')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusChip(
          label: _sourceLabel(preview.source),
          color: _sourceColor(preview.source),
          icon: _sourceIcon(preview.source),
        ),
        _StatusChip(
          label: preview.method.label,
          color: const Color(0xFF2563EB),
          icon: Icons.input_rounded,
        ),
        _StatusChip(
          label: '可导入 ${preview.validCount}',
          color: const Color(0xFF16A34A),
          icon: Icons.check_circle_rounded,
        ),
        _StatusChip(
          label: '重复 ${preview.duplicateCount}',
          color: const Color(0xFFB45309),
          icon: Icons.copy_all_rounded,
        ),
        _StatusChip(
          label: '错误 ${preview.errorCount}',
          color: const Color(0xFFDC2626),
          icon: Icons.error_outline_rounded,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.candidate});

  final ImportCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final color = candidate.error != null
        ? const Color(0xFFDC2626)
        : candidate.isDuplicate
        ? const Color(0xFFB45309)
        : const Color(0xFF16A34A);
    final label = candidate.error ?? (candidate.isDuplicate ? '重复' : '待确认');
    final visual = _visualForEntry(candidate.entry);
    final entry = candidate.entry;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          _EntryAvatar(visual: visual, size: 32, radius: 11),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                candidate.error != null
                    ? Icons.error_outline_rounded
                    : candidate.isDuplicate
                    ? Icons.copy_all_rounded
                    : Icons.check_circle_rounded,
                size: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        candidate.rawSummary.isEmpty
            ? '第 ${candidate.rowNumber} 行'
            : candidate.rawSummary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$label · ${visual.label} · ${_sourceLabel(entry.source)}',
      ),
      trailing: Text(
        formatMoney(entry.signedAmountCents, withSign: true),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: entry.type == EntryType.income
              ? const Color(0xFF0F9F6E)
              : const Color(0xFFE05252),
        ),
      ),
    );
  }
}

class _EntryAvatar extends StatelessWidget {
  const _EntryAvatar({
    required this.visual,
    this.size = 38,
    this.radius = 12,
    this.badgeIcon,
    this.badgeColor,
  });

  final _EntryVisual visual;
  final double size;
  final double radius;
  final IconData? badgeIcon;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final badge = badgeIcon;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: visual.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: visual.color.withValues(alpha: 0.10)),
            ),
            child: Icon(visual.icon, color: visual.color, size: size * 0.52),
          ),
          if (badge != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: size * 0.44,
                height: size * 0.44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                child: Icon(
                  badge,
                  size: size * 0.26,
                  color: badgeColor ?? visual.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryListPanel extends StatelessWidget {
  const _EntryListPanel({
    required this.title,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final List<LedgerEntry> entries;
  final ValueChanged<LedgerEntry> onEdit;
  final ValueChanged<LedgerEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const _EmptyState(label: '还没有流水')
          else
            ...entries.map(
              (entry) => _EntryTile(
                entry: entry,
                onEdit: () => onEdit(entry),
                onDelete: () => onDelete(entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchivePanel extends StatelessWidget {
  const _ArchivePanel({
    required this.archives,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DayArchive> archives;
  final ValueChanged<LedgerEntry> onEdit;
  final ValueChanged<LedgerEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '按天归档',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (archives.isEmpty)
            const _EmptyState(label: '归档会按交易日期自动生成')
          else
            ...archives.map((archive) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('yyyy年MM月dd日').format(archive.day),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          formatMoney(archive.netCents, withSign: true),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: archive.netCents >= 0
                                ? const Color(0xFF0F9F6E)
                                : const Color(0xFFE05252),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...archive.entries.map(
                      (entry) => _EntryTile(
                        entry: entry,
                        compact: true,
                        onEdit: () => onEdit(entry),
                        onDelete: () => onDelete(entry),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    this.compact = false,
  });

  final LedgerEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final amountColor = entry.type == EntryType.income
        ? const Color(0xFF0F9F6E)
        : const Color(0xFFE05252);
    final visual = _visualForEntry(entry);
    final sourceLabel = _sourceLabel(entry.source);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          _EntryAvatar(
            visual: visual,
            size: compact ? 34 : 38,
            radius: 12,
            badgeIcon: _isImportedSource(entry.source)
                ? _sourceIcon(entry.source)
                : null,
            badgeColor: _sourceColor(entry.source),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  [
                    entry.category,
                    if (_isImportedSource(entry.source)) sourceLabel,
                    if (entry.note.isNotEmpty) entry.note,
                    DateFormat('HH:mm').format(entry.occurredAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: compact ? 76 : 104,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatMoney(entry.signedAmountCents, withSign: true),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: amountColor,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '编辑',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }
}
