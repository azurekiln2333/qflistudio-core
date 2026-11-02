import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/api_client.dart';
import '../services/app_paths.dart';
import '../store/auth_store.dart';

class PointsPage extends StatefulWidget {
  const PointsPage({
    super.key,
    required this.auth,
    this.client,
    this.clock,
    this.cacheDirectory,
  });

  final AuthStore auth;

  /// API 入口；为空时使用线上单例。测试可注入隔离的客户端。
  final ApiClient? client;

  /// 今日日期来源；为空时取 [DateTime.now]。测试据此固定缓存日期。
  final DateTime Function()? clock;

  /// 缓存目录；为空时使用应用存储目录。返回 null 关闭磁盘缓存。
  final Future<String?> Function()? cacheDirectory;

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  int _points = 0;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _adminOrders = [];
  bool _loadingLedger = true;
  bool _loadingItems = true;
  bool _loadingOrders = true;
  bool _loadingAdminOrders = true;
  bool _redeeming = false;
  String? _error;
  File? _cacheFile;
  String? _cachedDay;

  bool get _admin => widget.auth.user?.isAdmin == true;
  int get _availablePoints => widget.auth.user?.points ?? _points;
  ApiClient get _api => widget.client ?? ApiClient.instance;
  String get _today {
    final now = (widget.clock ?? DateTime.now)();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    // 余额与角色会随刷新/登录变化，页面必须跟着重建：
    // 兑换按钮的可用态和管理员页签都依赖 auth。
    widget.auth.addListener(_onAuthChanged);
    _tokenForData = widget.auth.token;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreCache());
  }

  @override
  void didUpdateWidget(PointsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.auth != widget.auth) {
      oldWidget.auth.removeListener(_onAuthChanged);
      widget.auth.addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final token = widget.auth.token;
    // 换了账号（或从登出回到登录）就要重新拉数据：
    // 否则页面还显示上一个账号的余额与明细。
    if (token != _tokenForData) {
      _resetSections();
      if (token != null) unawaited(_load(force: true));
    }
    setState(() {});
  }

  /// 数据属于哪个账号的令牌；用于识别账号切换。
  String? _tokenForData;

  void _resetSections() {
    _tokenForData = widget.auth.token;
    _loadingLedger = true;
    _loadingItems = true;
    _loadingOrders = true;
    _loadingAdminOrders = true;
    _ledger = [];
    _items = [];
    _orders = [];
    _adminOrders = [];
    _cachedDay = null;
  }

  Future<void> _restoreCache() async {
    final userId = widget.auth.user?.id;
    final cacheDirectory = widget.cacheDirectory;
    final root = cacheDirectory == null
        ? await AppPaths.storageDirectory()
        : await cacheDirectory();
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

  /// [skipPointsSync] 用于兑换后的刷新：余额刚刚由兑换结果写入，
  /// 再次回写会重复调 `updatePoints`（磁盘失败时还会重复报错）。
  Future<void> _load({bool force = false, bool skipPointsSync = false}) async {
    final token = widget.auth.token;
    if (token == null) return;
    if (!force && _cachedDay == _today) return;
    try {
      // 各区块独立完成：兑换列表慢或失败，积分明细照样可看。
      // 每个 future 自己收尾，不能用一个 await 把其它区块挡在后面。
      Future<void> track(Future<void> work) => work;

      await Future.wait([
        track(() async {
          final history = await _api.pointHistory(token);
          if (!mounted || widget.auth.token != token) return;
          setState(() {
            _points = history.points;
            _ledger = history.entries;
            _loadingLedger = false;
          });
          // 只在服务端余额与本地不同时回写：相同就不必动磁盘，
          // 盘写失败也就没有机会把一次干净的加载变成异常。
          if (!skipPointsSync &&
              widget.auth.user?.points != history.points) {
            try {
              await widget.auth.updatePoints(points: history.points);
            } on Object {
              // 写盘失败不影响页面展示：余额已来自服务端。
            }
          }
        }()),
        track(() async {
          final items = await _api.rewardItems(token, admin: _admin);
          if (!mounted || widget.auth.token != token) return;
          setState(() {
            _items = items;
            _loadingItems = false;
            _cachedDay = _today;
            _error = null;
          });
        }()),
        track(() async {
          final orders = await _api.redemptions(token);
          if (!mounted || widget.auth.token != token) return;
          setState(() {
            _orders = orders;
            _loadingOrders = false;
          });
        }()),
        if (_admin)
          track(() async {
            final adminOrders = await _api.redemptions(token, admin: true);
            if (!mounted || widget.auth.token != token) return;
            setState(() {
              _adminOrders = adminOrders;
              _loadingAdminOrders = false;
            });
          }()),
      ]);
      await _persistCache();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          // 失败不能把其它区块一直停在转圈上。
          _loadingLedger = false;
          _loadingItems = false;
          _loadingOrders = false;
          _loadingAdminOrders = false;
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
    final token = widget.auth.token!;
    try {
      final points = await _api.redeem(token, item['id'] as String);
      // 请求在途时可能已经换了账号：旧账号的响应不能改写新账号的余额、
      // 不能弹提示，也不能触发刷新。
      if (!mounted || widget.auth.token != token) return;
      var localSaveFailed = false;
      try {
        await widget.auth.updatePoints(points: points);
      } on Object {
        // 服务端已经完成兑换；写盘失败时余额已在内存中生效，
        // 不能把兑换判为失败，但要告诉用户去刷新。
        localSaveFailed = true;
      }
      if (!mounted || widget.auth.token != token) return;
      setState(() => _points = points);
      _message(
        localSaveFailed ? '兑换已提交，但本地积分保存失败，请稍后刷新' : '兑换已提交',
      );
      // 兑换改变了库存、明细与订单，即使写盘失败也要刷新。
      await _load(force: true, skipPointsSync: true);
    } on ApiException catch (error) {
      if (!mounted || widget.auth.token != token) return;
      _message(error.message);
    } finally {
      if (mounted && widget.auth.token == token) {
        setState(() => _redeeming = false);
      }
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
      await _api.saveReward(
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
      await _api.fulfillRedemption(
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
              // 每个页签各自反映自己的数据状态：兑换列表还在路上时，
              // 积分明细仍然可读，不给整页一个转圈。
              child: TabBarView(
                children: [
                  _loadingItems
                      ? const Center(child: CircularProgressIndicator())
                      : _rewardList(),
                  _loadingLedger
                      ? const Center(child: CircularProgressIndicator())
                      : _ledgerList(),
                  _loadingOrders
                      ? const Center(child: CircularProgressIndicator())
                      : _orderList(_orders),
                  if (_admin)
                    _loadingAdminOrders
                        ? const Center(child: CircularProgressIndicator())
                        : _orderList(_adminOrders, admin: true),
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
            key: const PageStorageKey('points-rewards'),
            children: const [
              SizedBox(height: 80),
              Center(child: Text('暂无可兑换项')),
            ],
          )
        : ListView.builder(
            key: const PageStorageKey('points-rewards'),
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
            key: const PageStorageKey('points-ledger'),
            children: const [
              SizedBox(height: 80),
              Center(child: Text('暂无积分记录')),
            ],
          )
        : ListView.builder(
            key: const PageStorageKey('points-ledger'),
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
