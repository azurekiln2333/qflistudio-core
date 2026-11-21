import 'package:flutter/material.dart';

import '../tools/ported/models.dart' as netrix;
import '../tools/ported/netrix_localizations.dart';
import '../tools/ported/netrix_tool_page.dart';
import '../tools/ported_tool.dart';
import '../tools/ported_tools.dart';
import '../tools/tool_audience.dart';
import '../tools/tool_state_store.dart';
import 'tool_widgets.dart';

/// 工具页的一行内容，既有工具和移植工具共用。
///
/// 页面对两种来源的渲染完全相同：宽松显示是 [ToolCard]，紧密显示是
/// [ToolRow]。差别只有副标题文字和打开方式。
class ToolsBrowserEntry {
  const ToolsBrowserEntry({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    this.keywords = const <String>[],
    this.builder,
    this.onTap,
  });

  /// 从 netrix 移植来的工具。副标题按 netrix 的写法是「英文名 · 分类」。
  factory ToolsBrowserEntry.fromPorted(
    PortedToolEntry entry,
    String categoryLabel,
    ToolStateStore store,
  ) {
    return ToolsBrowserEntry(
      id: entry.tool.id,
      icon: entry.tool.icon,
      title: entry.tool.title,
      subtitle: '${entry.tool.titleEn} · $categoryLabel',
      description: entry.tool.description,
      keywords: <String>[
        entry.tool.titleEn,
        categoryLabel,
        entry.tool.category.key,
      ],
      builder: (_) => NetrixToolPage(tool: entry.tool, store: store),
    );
  }

  /// 稳定标识：移植工具用 netrix 的标识，既有工具用 `builtin:<标题>`。
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final List<String> keywords;
  final WidgetBuilder? builder;
  final VoidCallback? onTap;

  bool matches(String query) {
    if (query.isEmpty) return true;
    return <String>[
      title,
      subtitle,
      description,
      ...keywords,
    ].any((value) => value.toLowerCase().contains(query));
  }
}

/// 工具页的一个分组。
class ToolsBrowserSection {
  const ToolsBrowserSection({
    required this.title,
    required this.icon,
    required this.entries,
    this.categoryKey,
  });

  final String title;
  final IconData icon;
  final List<ToolsBrowserEntry> entries;

  /// 移植工具所属分类的键；既有工具分组为 null。
  final String? categoryKey;
}

/// netrix 工具页的宿主版本。
///
/// 界面元素与 netrix 的「全部工具」页一致：搜索框、分类筛选、显示密度切换、
/// 工具卡与紧凑行、收藏、最近使用和空态提示。既有工具和移植来的 netrix 工具
/// 走同一套渲染，所以两种显示密度对工具页的全部工具生效。
///
/// 移植来的工具由 [visiblePortedTools] 按可见范围过滤：子项目下这个列表为空，
/// 页面照常显示既有工具，框架和两种密度完全一致。
class ToolsBrowser extends StatefulWidget {
  const ToolsBrowser({
    super.key,
    required this.sections,
    required this.state,
    this.isMainApp,
  });

  /// 既有工具分组，标题和顺序由调用方给出。
  final List<ToolsBrowserSection> sections;

  /// 显示密度、列数、收藏和使用记录。
  final ToolStateStore state;

  /// 可见范围覆盖，仅供测试；null 时按 `StudioProfile.current` 判定。
  final bool? isMainApp;

  @override
  State<ToolsBrowser> createState() => _ToolsBrowserState();
}

class _ToolsBrowserState extends State<ToolsBrowser> {
  final TextEditingController _search = TextEditingController();
  netrix.ToolCategory? _category;

  ToolStateStore get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _state.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ToolsBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_refresh);
      _state.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _state.removeListener(_refresh);
    _search
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _query => _search.text.trim().toLowerCase();

  bool get _filtering => _query.isNotEmpty || _category != null;

  /// 当前可见的分组：既有分组在前，移植工具按 netrix 分类跟在后面。
  List<ToolsBrowserSection> _allSections(BuildContext context) {
    final strings = NetrixLocalizations.of(context);
    final isMainApp = widget.isMainApp ?? ToolScope.of(context);
    final ported = portedToolsInScope(isMainApp: isMainApp);
    return <ToolsBrowserSection>[
      ...widget.sections,
      for (final category in portedCategoriesOrder)
        if (ported.any((entry) => entry.tool.category == category))
          ToolsBrowserSection(
            title: strings.category(category.key),
            icon: category.icon,
            categoryKey: category.key,
            entries: <ToolsBrowserEntry>[
              for (final entry in ported)
                if (entry.tool.category == category)
                  ToolsBrowserEntry.fromPorted(
                    entry,
                    strings.category(category.key),
                    _state,
                  ),
            ],
          ),
    ];
  }

  List<ToolsBrowserSection> _visibleSections(
    List<ToolsBrowserSection> sections,
  ) {
    final selected = _category?.key;
    return <ToolsBrowserSection>[
      for (final section in sections)
        if (selected == null || section.categoryKey == selected)
          ToolsBrowserSection(
            title: section.title,
            icon: section.icon,
            categoryKey: section.categoryKey,
            entries: <ToolsBrowserEntry>[
              for (final entry in section.entries)
                if (entry.matches(_query)) entry,
            ],
          ),
    ].where((section) => section.entries.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final strings = NetrixLocalizations.of(context);
    final all = _allSections(context);
    final sections = _visibleSections(all);
    final byId = <String, ToolsBrowserEntry>{
      for (final section in all)
        for (final entry in section.entries) entry.id: entry,
    };
    final recent = <ToolsBrowserEntry>[
      if (!_filtering)
        for (final id in _state.recent) ?byId[id],
    ];
    final horizontal = ToolsTheme.horizontalPadding(
      MediaQuery.sizeOf(context).width,
    );

    return CustomScrollView(
      key: const PageStorageKey<String>('tools-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 0),
          sliver: SliverToBoxAdapter(
            child: _ToolsBrowserHeader(
              searchController: _search,
              category: _category,
              categories: _categoryKeys(all),
              density: _state.density,
              cardColumns: _state.cardColumns,
              onCategoryChanged: (value) => setState(() => _category = value),
              onDensityChanged: _state.setDensity,
              onCardColumnsChanged: _state.setCardColumns,
              strings: strings,
            ),
          ),
        ),
        if (sections.isEmpty && recent.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyTools(
                title: strings.noMatchingTools,
                description: strings.noMatchingToolsDescription,
                icon: Icons.search_off_outlined,
              ),
            ),
          )
        else ...<Widget>[
          if (recent.isNotEmpty) ...<Widget>[
            _headingSliver(
              horizontal,
              strings.recentTools,
              strings.recentToolsCount(recent.length),
              Icons.history,
            ),
            _entriesSliver(horizontal, recent, 18),
          ],
          for (final section in sections) ...<Widget>[
            _headingSliver(horizontal, section.title, null, section.icon),
            _entriesSliver(horizontal, section.entries, 18),
          ],
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 32),
            sliver: const SliverToBoxAdapter(child: _OfflineNote()),
          ),
        ],
      ],
    );
  }

  /// 分类筛选条的取值：只有存在移植工具的分类才显示。
  List<netrix.ToolCategory> _categoryKeys(List<ToolsBrowserSection> sections) {
    final keys = <String>{for (final section in sections) ?section.categoryKey};
    return <netrix.ToolCategory>[
      for (final category in portedCategoriesOrder)
        if (keys.contains(category.key)) category,
    ];
  }

  Widget _headingSliver(
    double horizontal,
    String title,
    String? subtitle,
    IconData icon,
  ) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 8),
      sliver: SliverToBoxAdapter(
        child: ToolsSectionHeading(
          icon: icon,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
  }

  Widget _entriesSliver(
    double horizontal,
    List<ToolsBrowserEntry> entries,
    double bottom,
  ) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottom),
      sliver: _state.density == ToolCardDensity.compact
          ? _rowsSliver(entries)
          : _cardsSliver(entries),
    );
  }

  /// 宽松显示：按用户选择固定为一列或两列。
  Widget _cardsSliver(List<ToolsBrowserEntry> entries) {
    final strings = NetrixLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final extraTextHeight =
        _extraLineHeight(scaler, textTheme.titleMedium, 16) +
        2 * _extraLineHeight(scaler, textTheme.bodySmall, 12);
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = entries[index];
        final isFavorite = _state.favorites.contains(entry.id);
        return ToolCard(
          icon: entry.icon,
          title: entry.title,
          description: entry.description,
          onTap: () => _open(context, entry),
          isFavorite: isFavorite,
          onToggleFavorite: () => _state.toggleFavorite(entry.id),
          favoriteTooltip: isFavorite
              ? strings.removeFavorite
              : strings.addFavorite,
          openTooltip: strings.openTool,
        );
      }, childCount: entries.length),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _state.cardColumns,
        mainAxisExtent: ToolsTheme.cardHeight + extraTextHeight,
        crossAxisSpacing: ToolsTheme.cardSpacing,
        mainAxisSpacing: ToolsTheme.cardSpacing,
      ),
    );
  }

  /// 紧密显示：每行一个工具，与 netrix 的紧凑行一致。
  Widget _rowsSliver(List<ToolsBrowserEntry> entries) {
    final strings = NetrixLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final extraTextHeight =
        _extraLineHeight(scaler, textTheme.titleSmall, 14) +
        _extraLineHeight(scaler, textTheme.bodySmall, 12);
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = entries[index];
        final isFavorite = _state.favorites.contains(entry.id);
        return SizedBox(
          height: 78 + extraTextHeight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ToolRow(
              icon: entry.icon,
              title: entry.title,
              subtitle: entry.subtitle,
              onTap: () => _open(context, entry),
              isFavorite: isFavorite,
              onToggleFavorite: () => _state.toggleFavorite(entry.id),
              favoriteTooltip: isFavorite
                  ? strings.removeFavorite
                  : strings.addFavorite,
              openTooltip: strings.openTool,
            ),
          ),
        );
      }, childCount: entries.length),
    );
  }

  static double _extraLineHeight(
    TextScaler scaler,
    TextStyle? style,
    double fallbackSize,
  ) {
    final size = style?.fontSize ?? fallbackSize;
    return (scaler.scale(size) - size).clamp(0.0, double.infinity) *
        (style?.height ?? 1.5);
  }

  /// 打开一个条目：既有工具用自带页面或回调，移植工具用 netrix 详情页。
  void _open(BuildContext context, ToolsBrowserEntry entry) {
    if (entry.onTap != null) {
      entry.onTap!();
      return;
    }
    final builder = entry.builder;
    if (builder == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }
}

class _ToolsBrowserHeader extends StatelessWidget {
  const _ToolsBrowserHeader({
    required this.searchController,
    required this.category,
    required this.categories,
    required this.density,
    required this.cardColumns,
    required this.onCategoryChanged,
    required this.onDensityChanged,
    required this.onCardColumnsChanged,
    required this.strings,
  });

  final TextEditingController searchController;
  final netrix.ToolCategory? category;
  final List<netrix.ToolCategory> categories;
  final ToolCardDensity density;
  final int cardColumns;
  final ValueChanged<netrix.ToolCategory?> onCategoryChanged;
  final ValueChanged<ToolCardDensity> onDensityChanged;
  final ValueChanged<int> onCardColumnsChanged;
  final NetrixLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: strings.searchTools,
          ),
        ),
        if (categories.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                FilterChip(
                  label: Text(strings.all),
                  selected: category == null,
                  onSelected: (_) => onCategoryChanged(null),
                ),
                const SizedBox(width: 8),
                for (final item in categories) ...<Widget>[
                  FilterChip(
                    avatar: Icon(item.icon, size: 17),
                    label: Text(strings.category(item.key)),
                    selected: category == item,
                    onSelected: (_) => onCategoryChanged(item),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ToolCardDensity>(
                  segments: <ButtonSegment<ToolCardDensity>>[
                    ButtonSegment<ToolCardDensity>(
                      value: ToolCardDensity.standard,
                      icon: const Icon(Icons.view_agenda_outlined),
                      label: Text(strings.standard),
                    ),
                    ButtonSegment<ToolCardDensity>(
                      value: ToolCardDensity.compact,
                      icon: const Icon(Icons.view_compact_outlined),
                      label: Text(strings.compact),
                    ),
                  ],
                  selected: <ToolCardDensity>{density},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) {
                    if (values.isNotEmpty) onDensityChanged(values.first);
                  },
                ),
              ),
              if (density == ToolCardDensity.standard)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    segments: <ButtonSegment<int>>[
                      ButtonSegment<int>(
                        value: 1,
                        icon: const Icon(Icons.view_agenda_outlined),
                        label: Text(strings.oneColumn),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        icon: const Icon(Icons.view_column_outlined),
                        label: Text(strings.twoColumns),
                      ),
                    ],
                    selected: <int>{cardColumns},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) {
                      if (values.isNotEmpty) onCardColumnsChanged(values.first);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyTools extends StatelessWidget {
  const _EmptyTools({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title),
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.offline_bolt_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '通用工具均在本机离线计算，不会上传任何内容。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
