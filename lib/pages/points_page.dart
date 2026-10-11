import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/api_client.dart';
import '../services/app_paths.dart';
import '../store/auth_store.dart';

class PointsPage extends StatefulWidget {
  const PointsPage({super.key, required this.auth});

  final AuthStore auth;

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  int _points = 0;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _adminOrders = [];
  bool _loading = true;
  bool _redeeming = false;
  String? _error;
  File? _cacheFile;
  String? _cachedDay;

  bool get _admin => widget.auth.user?.isAdmin == true;
  int get _availablePoints => widget.auth.user?.points ?? _points;
  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreCache());
  }

  Future<void> _restoreCache() async {
    final userId = widget.auth.user?.id;
    final root = await AppPaths.storageDirectory();
    if (root != null && userId != null) {
      _cacheFile = File(p.join(root, 'points_$userId.json'));
      try {
        final data =
            jsonDecode(await _cacheFile!.readAsString())
                as Map<String, dynamic>;
        if (mounted && widget.auth.user?.id == userId) {
          setState(() {
            _cachedDay = data['day'] as String?;
            _points = (data['points'] as num).toInt();
            _items = _cachedRows(data['items']);
            _ledger = _cachedRows(data['ledger']);
            _orders = _cachedRows(data['orders']);
            _adminOrders = _cachedRows(data['adminOrders']);
            _loading = false;
          });
        }
      } on Object {
        // A missing or damaged cache is replaced by the next successful fetch.
      }
    }
    if (mounted) await _load();
  }

  List<Map<String, dynamic>> _cachedRows(Object? rows) => [
    for (final row in rows as List? ?? const [])
      Map<String, dynamic>.from(row as Map),
  ];

  Future<void> _persistCache() async {
    final file = _cacheFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'day': _cachedDay,
          'points': _points,
          'items': _items,
          'ledger': _ledger,
          'orders': _orders,
          'adminOrders': _adminOrders,
        }),
        flush: true,
      );
    } on FileSystemException {
      // The live result remains usable when local storage is unavailable.
    }
  }

  Future<void> _load({bool force = false}) async {
    final token = widget.auth.token;
    if (token == null) return;
    if (!force && _cachedDay == _today) return;
    final startingPoints = widget.auth.user?.points;
    try {
      final history = await ApiClient.instance.pointHistory(token);
      final items = await ApiClient.instance.rewardItems(token, admin: _admin);
      final orders = await ApiClient.instance.redemptions(token);
      final adminOrders = _admin
          ? await ApiClient.instance.redemptions(token, admin: true)
          : <Map<String, dynamic>>[];
      if (!mounted || widget.auth.token != token) return;
      setState(() {
        _points = history.points;
        _ledger = history.entries;
        _items = items;
        _orders = orders;
        _adminOrders = adminOrders;
        _cachedDay = _today;
        _error = null;
        _loading = false;
      });
      if (widget.auth.user?.points == startingPoints) {
        await widget.auth.updatePoints(points: history.points);
      }
      await _persistCache();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _redeem(Map<String, dynamic> item) async {
    if (_redeeming) return;
    setState(() => _redeeming = true);
    final cost = (item['cost'] as num).toInt();
    if (_availablePoints < cost) {
      _message('积分不足');
      setState(() => _redeeming = false);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认兑换'),
        content: Text('使用 $cost 积分兑换 ${item['title']}？兑换后由管理员处理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('兑换'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _redeeming = false);
      return;
    }
    try {
      final token = widget.auth.token!;
      final points = await ApiClient.instance.redeem(
        token,
        item['id'] as String,
      );
      await widget.auth.updatePoints(points: points);
      if (mounted) setState(() => _points = points);
      _message('兑换已提交');
      await _load(force: true);
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _editReward([Map<String, dynamic>? item]) async {
    final title = TextEditingController(text: item?['title'] as String? ?? '');
    final description = TextEditingController(
      text: item?['description'] as String? ?? '',
    );
    final cost = TextEditingController(text: item?['cost']?.toString() ?? '');
    final stock = TextEditingController(
      text: item?['stock']?.toString() ?? '-1',
    );
    var enabled = item?['enabled'] != 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? '新增兑换项' : '编辑兑换项'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  TextField(
                    controller: description,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '说明'),
                  ),
                  TextField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '所需积分'),
                  ),
                  TextField(
                    controller: stock,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: '库存（-1 为不限量）'),
                  ),
                  if (item != null)
                    SwitchListTile(
                      title: const Text('上架'),
                      value: enabled,
                      onChanged: (value) =>
                          setDialogState(() => enabled = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final name = title.text.trim();
    final detail = description.text.trim();
    final price = int.tryParse(cost.text.trim());
    final quantity = int.tryParse(stock.text.trim());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    description.dispose();
    cost.dispose();
    stock.dispose();
    if (saved != true) return;
    if (name.isEmpty ||
        price == null ||
        price < 1 ||
        price > 1000000 ||
        quantity == null ||
        quantity < -1) {
      _message('请填写有效的名称、积分和库存');
      return;
    }
    try {
      await ApiClient.instance.saveReward(
        widget.auth.token!,
        id: item?['id'] as String?,
        title: name,
        description: detail,
        cost: price,
        stock: quantity,
        enabled: enabled,
      );
      await _load(force: true);
    } on ApiException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _fulfill(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认已处理'),
        content: Text('确认兑换“${order['item_title']}”已经交付？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.fulfillRedemption(
        widget.auth.token!,
        order['id'] as String,
      );
      await _load(force: true);
    } on ApiException catch (error) {
      _message(error.message);
    }
  }

  String _kind(Map<String, dynamic> entry) => switch (entry['kind']) {
    'checkin' => '每日签到',
    'task' => switch ((entry['reference_id'] as String).split(':').last) {
      'create_project' => '创建项目 (1 次)',
      'create_project_5' => '创建项目 (5 次)',
      'create_project_10' => '创建项目 (10 次)',
      'open_project' => '打开项目 (1 次)',
      'open_project_5' => '打开项目 (5 次)',
      'open_project_10' => '打开项目 (10 次)',
      'save_file' => '修改文件 (1 次)',
      'save_file_5' => '修改文件 (5 次)',
      'save_file_10' => '修改文件 (10 次)',
      _ => '每日任务',
    },
    'redeem' => '积分兑换',
    _ => '积分变动',
  };

  @override
  Widget build(BuildContext context) {
    final tabs = _admin ? 4 : 3;
    return DefaultTabController(
      length: tabs,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('积分兑换'),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () => _load(force: true),
            ),
            if (_admin)
              IconButton(
                tooltip: '新增兑换项',
                icon: const Icon(Icons.add),
                onPressed: () => _editReward(),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.stars_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('可用积分')),
                  Text(
                    '$_availablePoints',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            TabBar(
              isScrollable: true,
              tabs: [
                const Tab(text: '兑换'),
                const Tab(text: '积分明细'),
                const Tab(text: '我的兑换'),
                if (_admin) const Tab(text: '待处理'),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _rewardList(),
                        _ledgerList(),
                        _orderList(_orders),
                        if (_admin) _orderList(_adminOrders, admin: true),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardList() => RefreshIndicator(
    onRefresh: () => _load(force: true),
    child: _items.isEmpty
        ? ListView(
            children: const [
              SizedBox(height: 80),
              Center(child: Text('暂无可兑换项')),
            ],
          )
        : ListView.builder(
            itemCount: _items.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final item = _items[index];
              final cost = (item['cost'] as num).toInt();
              final stock = (item['stock'] as num).toInt();
              final available = item['enabled'] != 0 && stock != 0;
              return Card(
                child: ListTile(
                  title: Text(item['title'] as String),
                  subtitle: Text(
                    '${item['description'] as String}${stock >= 0 ? '\n剩余 $stock' : ''}',
                  ),
                  isThreeLine:
                      (item['description'] as String).isNotEmpty && stock >= 0,
                  trailing: _admin
                      ? IconButton(
                          tooltip: '编辑兑换项',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editReward(item),
                        )
                      : FilledButton(
                          onPressed:
                              !_redeeming &&
                                  available &&
                                  _availablePoints >= cost
                              ? () => _redeem(item)
                              : null,
                          child: Text('$cost 积分'),
                        ),
                ),
              );
            },
          ),
  );

  Widget _ledgerList() => RefreshIndicator(
    onRefresh: () => _load(force: true),
    child: _ledger.isEmpty
        ? ListView(
            children: const [
              SizedBox(height: 80),
              Center(child: Text('暂无积分记录')),
            ],
          )
        : ListView.builder(
            itemCount: _ledger.length,
            itemBuilder: (context, index) {
              final entry = _ledger[index];
              final amount = (entry['amount'] as num).toInt();
              return ListTile(
                leading: Icon(
                  amount >= 0
                      ? Icons.add_circle_outline
                      : Icons.remove_circle_outline,
                ),
                title: Text(_kind(entry)),
                subtitle: Text(
                  '${entry['created_at']} · 余额 ${entry['balance_after']}',
                ),
                trailing: Text(
                  '${amount > 0 ? '+' : ''}$amount',
                  style: TextStyle(
                    color: amount >= 0
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              );
            },
          ),
  );

  Widget _orderList(List<Map<String, dynamic>> orders, {bool admin = false}) =>
      RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('暂无兑换记录')),
                ],
              )
            : ListView.builder(
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final pending = order['status'] == 'pending';
                  return ListTile(
                    title: Text(order['item_title'] as String),
                    subtitle: Text(
                      '${order['created_at']} · ${order['cost']} 积分'
                      '${admin ? '\n${order['user_id']}' : ''}',
                    ),
                    isThreeLine: admin,
                    trailing: admin && pending
                        ? IconButton(
                            tooltip: '标记已处理',
                            icon: const Icon(Icons.task_alt),
                            onPressed: () => _fulfill(order),
                          )
                        : Text(pending ? '待处理' : '已完成'),
                  );
                },
              ),
      );
}
