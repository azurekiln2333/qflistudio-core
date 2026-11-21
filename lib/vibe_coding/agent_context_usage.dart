/// Read-only local context estimates and the last provider-reported input.
library;

import 'dart:convert';

enum AgentContextCategory {
  systemPrompt,
  projectRules,
  skills,
  messages,
  tools,
  mcp,
  other,
}

class AgentContextUsage {
  const AgentContextUsage({
    this.estimatedInputTokens = 0,
    this.lastReportedInputTokens,
    this.estimatedBreakdown = const {},
    this.historyLoaded = true,
  });

  const AgentContextUsage.empty({this.historyLoaded = false})
    : estimatedInputTokens = 0,
      lastReportedInputTokens = null,
      estimatedBreakdown = const {};

  /// Estimate for the history currently prepared for the next request.
  final int estimatedInputTokens;

  /// Input count reported for the last completed request, not current history.
  /// Provider cache fields retain their own semantics and are not added here.
  final int? lastReportedInputTokens;

  /// Mutually exclusive local estimates. These sum to [estimatedInputTokens].
  /// MCP stays zero until the runtime actually contributes MCP context.
  final Map<AgentContextCategory, int> estimatedBreakdown;

  /// False while the facade has not restored the complete model history.
  final bool historyLoaded;

  AgentContextUsage copyWith({bool? historyLoaded}) => AgentContextUsage(
    estimatedInputTokens: estimatedInputTokens,
    lastReportedInputTokens: lastReportedInputTokens,
    estimatedBreakdown: estimatedBreakdown,
    historyLoaded: historyLoaded ?? this.historyLoaded,
  );
}

/// Estimates the actual request history without reading UI transcript summaries.
///
/// The runtime does not have provider tokenizers. The deliberately approximate
/// rule budgets one token per non-ASCII scalar and one per four ASCII scalars.
/// Protocol adapters may add or reshape text, so even structural costs remain
/// estimates. No local estimate is presented as provider-reported usage.
AgentContextUsage estimateAgentContextUsage({
  required List<Map<String, dynamic>> history,
  required List<Map<String, dynamic>> tools,
  required Map<AgentContextCategory, String> systemSections,
  int? lastReportedInputTokens,
}) {
  final counts = <AgentContextCategory, int>{
    for (final category in AgentContextCategory.values) category: 0,
  };

  void add(AgentContextCategory category, String text) {
    counts[category] = counts[category]! + _estimateTokens(text);
  }

  void addSystem(String content) {
    var remaining = content;
    for (final section in systemSections.entries) {
      if (section.value.isEmpty) continue;
      final start = remaining.indexOf(section.value);
      if (start < 0) continue;
      add(section.key, section.value);
      remaining = remaining.replaceRange(
        start,
        start + section.value.length,
        '',
      );
    }
    // Only actual, still-present sections are attributed after history trims.
    add(AgentContextCategory.systemPrompt, remaining);
  }

  final toolNames = <String, String>{};
  for (final entry in history) {
    final remaining = Map<String, dynamic>.from(entry);
    final role = entry['role'];
    final calls = remaining.remove('tool_calls');
    if (calls != null) {
      add(AgentContextCategory.tools, jsonEncode(calls));
      if (calls is List) {
        for (final call in calls) {
          if (call is! Map) continue;
          final id = call['id'];
          final function = call['function'];
          if (id is String && function is Map && function['name'] is String) {
            toolNames[id] = function['name'] as String;
          }
        }
      }
    }
    final content = remaining.remove('content');
    if (content is String) {
      if (role == 'system') {
        addSystem(content);
      } else if (role == 'tool') {
        add(
          toolNames[entry['tool_call_id']] == 'use_skill'
              ? AgentContextCategory.skills
              : AgentContextCategory.tools,
          content,
        );
      } else if (role == 'user' || role == 'assistant') {
        add(AgentContextCategory.messages, content);
      } else {
        add(AgentContextCategory.other, content);
      }
    } else if (content != null) {
      add(AgentContextCategory.other, jsonEncode(content));
    }
    // Role/id fields, reasoning blocks and other message metadata live here.
    add(AgentContextCategory.other, jsonEncode(remaining));
  }
  if (tools.isNotEmpty) add(AgentContextCategory.tools, jsonEncode(tools));
  return AgentContextUsage(
    estimatedInputTokens: counts.values.fold(0, (sum, count) => sum + count),
    lastReportedInputTokens: lastReportedInputTokens,
    estimatedBreakdown: Map.unmodifiable(counts),
  );
}

int _estimateTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (final rune in text.runes) {
    if (rune <= 0x7f) {
      ascii++;
    } else {
      other++;
    }
  }
  return other + (ascii + 3) ~/ 4;
}
