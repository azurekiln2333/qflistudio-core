/// 任务计划（`todo` 工具）：解析、校验与展示快照。
///
/// 模型一次提交完整计划，控制器整体替换当前计划，避免留下过期步骤。
library;

/// 计划条目状态。
enum VibePlanStatus { pending, doing, done }

/// 计划条目的只读快照。
class VibePlanItem {
  const VibePlanItem({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final VibePlanStatus status;

  String get statusLabel => switch (status) {
    VibePlanStatus.pending => '待办',
    VibePlanStatus.doing => '进行中',
    VibePlanStatus.done => '已完成',
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
  };
}

/// 计划上限：条目数、标题长度。
const int kVibeMaxPlanItems = 20;
const int kVibeMaxPlanTitleChars = 120;

/// 计划参数无效时抛出；控制器转成工具错误交给模型。
class VibePlanException implements Exception {
  const VibePlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析 `todo` 工具的 `items` 参数。
///
/// 拒绝空计划、超过上限、空标题、重复 id、未知状态和多个进行中条目。
List<VibePlanItem> parseVibePlan(Object? rawItems) {
  if (rawItems is! List) {
    throw const VibePlanException('items 必须是数组');
  }
  if (rawItems.isEmpty) {
    throw const VibePlanException('items 不能为空；完成全部步骤时把状态改为 done');
  }
  if (rawItems.length > kVibeMaxPlanItems) {
    throw const VibePlanException('计划最多 $kVibeMaxPlanItems 个条目');
  }
  final items = <VibePlanItem>[];
  final seenIds = <String>{};
  var doing = 0;
  for (var i = 0; i < rawItems.length; i++) {
    final entry = rawItems[i];
    if (entry is! Map) {
      throw VibePlanException('第 ${i + 1} 个条目必须是对象');
    }
    final title = entry['title'];
    if (title is! String || title.trim().isEmpty) {
      throw VibePlanException('第 ${i + 1} 个条目缺少 title');
    }
    if (title.trim().length > kVibeMaxPlanTitleChars) {
      throw VibePlanException('第 ${i + 1} 个条目标题超过 $kVibeMaxPlanTitleChars 字符');
    }
    final rawId = entry['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : '${i + 1}';
    if (!seenIds.add(id)) {
      throw VibePlanException('条目 id 重复：$id');
    }
    final rawStatus = entry['status'];
    final status = switch (rawStatus) {
      null => VibePlanStatus.pending,
      'pending' => VibePlanStatus.pending,
      'doing' => VibePlanStatus.doing,
      'done' => VibePlanStatus.done,
      _ => throw VibePlanException('条目 $id 的 status 只能是 pending、doing 或 done'),
    };
    if (status == VibePlanStatus.doing) doing++;
    items.add(VibePlanItem(id: id, title: title.trim(), status: status));
  }
  if (doing > 1) {
    throw const VibePlanException('最多只能有一个条目处于 doing');
  }
  return List.unmodifiable(items);
}

/// 计划是否全部完成；空计划视为未完成。
bool vibePlanAllDone(List<VibePlanItem> items) =>
    items.isNotEmpty &&
    items.every((item) => item.status == VibePlanStatus.done);

/// 计划摘要：给模型看的真实状态。
String describeVibePlan(List<VibePlanItem> items) {
  final done = items.where((i) => i.status == VibePlanStatus.done).length;
  final lines = items
      .map((item) => '- [${item.status.name}] ${item.id}. ${item.title}')
      .join('\n');
  return '计划已更新：$done/${items.length} 完成\n$lines';
}
