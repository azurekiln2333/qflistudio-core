import 'package:flutter/material.dart';

import '../services/app_restore_gate.dart';

class RestoreCompletePage extends StatelessWidget {
  const RestoreCompletePage({super.key, required this.status});

  final AppRestoreStatus status;

  @override
  Widget build(BuildContext context) {
    final completed = status == AppRestoreStatus.completed;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    completed ? Icons.check_circle_outline : Icons.restore,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    completed ? '数据恢复完成' : '数据恢复尚未完成',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    completed
                        ? '请从最近任务中完全关闭应用，然后重新打开，使用恢复后的数据。'
                        : '为避免使用不完整的数据，应用已暂停启动。请从最近任务中完全关闭应用，然后重新打开。'
                              '若问题持续，请保留应用数据与原备份文件。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
