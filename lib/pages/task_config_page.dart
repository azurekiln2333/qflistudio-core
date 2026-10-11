import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../store/auth_store.dart';

class TaskConfigPage extends StatefulWidget {
  const TaskConfigPage({super.key, required this.auth});
  final AuthStore auth;

  @override
  State<TaskConfigPage> createState() => _TaskConfigPageState();
}

class _TaskConfigPageState extends State<TaskConfigPage> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final tasks = await ApiClient.instance.taskConfig(widget.auth.token!);
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _error = null;
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> task) async {
    final controller = TextEditingController(text: task['reward'].toString());
    final targetController = TextEditingController(
      text: (task['target_count'] ?? 1).toString(),
    );
    var enabled = task['enabled'] != 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(task['label'] as String),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '基础积分'),
              ),
              TextField(
                controller: targetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '完成次数'),
              ),
              SwitchListTile(
                title: const Text('启用任务'),
                value: enabled,
                onChanged: (value) => update(() => enabled = value),
              ),
            ],
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
    final reward = int.tryParse(controller.text.trim());
    final targetCount = int.tryParse(targetController.text.trim());
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    targetController.dispose();
    if (saved != true) return;
    if (reward == null || reward < 0 || reward > 1000) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('积分需为 0 至 1000 的整数')));
      }
      return;
    }
    if (targetCount == null || targetCount < 1 || targetCount > 100) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('完成次数需为 1 至 100 的整数')));
      }
      return;
    }
    try {
      await ApiClient.instance.updateTaskConfig(
        widget.auth.token!,
        task['key'] as String,
        reward,
        enabled,
        targetCount,
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('任务配置'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : ListView(
            children: [
              for (final task in _tasks)
                ListTile(
                  title: Text(task['label'] as String),
                  subtitle: Text(
                    task['enabled'] == 0
                        ? '已停用'
                        : '每日完成 ${task['target_count'] ?? 1} 次',
                  ),
                  trailing: Text('${task['reward']} 积分'),
                  onTap: () => _edit(task),
                ),
            ],
          ),
  );
}
