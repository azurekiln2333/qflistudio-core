import 'dart:io';

import 'package:flutter/material.dart';

import '../content/asset_content_repository.dart';
import '../content/content_repository.dart';
import '../content/local_content_adapter.dart';
import '../i18n/studio_localizations.dart';
import '../models/tutorial.dart';
import '../services/studio_profile.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import '../store/settings_store.dart';
import '../services/example_code_store.dart';
import '../widgets/code_snippet.dart';
import '../widgets/language_badge.dart';

/// 离线语言 App 的第二页：从随包 JSON 加载入门教程。
class LocalTutorialsTab extends StatefulWidget {
  const LocalTutorialsTab({
    super.key,
    required this.language,
    this.repository,
    this.store,
    this.auth,
    this.settings,
  });

  final String language;
  final ContentRepository? repository;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;

  @override
  State<LocalTutorialsTab> createState() => _LocalTutorialsTabState();
}

class _LocalTutorialsTabState extends State<LocalTutorialsTab> {
  late ContentRepository _repository;
  late Future<Tutorial?> _tutorial;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AssetContentRepository();
    _tutorial = _loadTutorial();
  }

  @override
  void didUpdateWidget(covariant LocalTutorialsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language ||
        oldWidget.repository != widget.repository) {
      _repository = widget.repository ?? AssetContentRepository();
      _tutorial = _loadTutorial();
    }
  }

  Future<Tutorial?> _loadTutorial() => LocalContentAdapter.loadTutorial(
    repository: _repository,
    language: widget.language,
    displayName: _displayName(widget.language),
    productKey: StudioProfile.current?.productKey,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.tutorial,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      body: FutureBuilder<Tutorial?>(
        future: _tutorial,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tutorial = snapshot.data;
          if (tutorial == null) {
            return _LocalContentError(message: l10n.localTutorialMissing);
          }
          return _TutorialList(
            tutorial: tutorial,
            store: widget.store,
            auth: widget.auth,
            settings: widget.settings,
          );
        },
      ),
    );
  }
}

/// 离线语言 App 的第三页：展示教程 JSON 中的可复制示例代码。
class ExampleCodeTab extends StatefulWidget {
  const ExampleCodeTab({
    super.key,
    required this.language,
    this.repository,
    this.store,
    this.auth,
    this.settings,
    this.examples,
  });

  final String language;
  final ContentRepository? repository;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;
  final ExampleCodeStore? examples;

  @override
  State<ExampleCodeTab> createState() => _ExampleCodeTabState();
}

class _ExampleCodeTabState extends State<ExampleCodeTab> {
  late ContentRepository _repository;
  late Future<List<ExampleCode>> _examples;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AssetContentRepository();
    _examples = _loadExamples();
  }

  @override
  void didUpdateWidget(covariant ExampleCodeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language ||
        oldWidget.repository != widget.repository ||
        oldWidget.examples != widget.examples) {
      _repository = widget.repository ?? AssetContentRepository();
      _examples = _loadExamples();
    }
  }

  Future<List<ExampleCode>> _loadExamples() async {
    final store = widget.examples;
    final bundled = await LocalContentAdapter.loadExamples(
      repository: _repository,
      language: widget.language,
      productKey: StudioProfile.current?.productKey,
    );
    if (mounted) {
      try {
        await store?.load(defaults: bundled);
      } on FileSystemException {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                StudioLocalizations.of(context).savedExamplesUnavailable,
              ),
            ),
          );
        });
      }
    }
    final key = StudioProfile.current?.productKey;
    final allowed = key == null || key == StudioProductCatalog.qfliStudioKey
        ? null
        : ContentProductTypes.byProduct[key];
    return (store?.items ?? bundled)
        .where(
          (example) => allowed == null
              ? (example.language.isEmpty ? example.type : example.language)
                        .trim()
                        .toLowerCase() ==
                    widget.language.trim().toLowerCase()
              : allowed.contains(languageKey(example.type)),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.examples,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      body: FutureBuilder<List<ExampleCode>>(
        future: _examples,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final examples = snapshot.data;
          if (examples == null || examples.isEmpty) {
            return _LocalContentError(message: l10n.localExamplesMissing);
          }
          return _ExampleCodeList(
            items: examples,
            store: widget.store,
            auth: widget.auth,
            settings: widget.settings,
            examples: widget.examples,
          );
        },
      ),
    );
  }
}

class _TutorialList extends StatefulWidget {
  const _TutorialList({
    required this.tutorial,
    this.store,
    this.auth,
    this.settings,
  });

  final Tutorial tutorial;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;

  @override
  State<_TutorialList> createState() => _TutorialListState();
}

class _TutorialListState extends State<_TutorialList> {
  final _filter = _ContentFilterSelection();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lessons = widget.tutorial.allLessons;
    // Only row metadata is flattened here; widgets are created on demand.
    final rows = <({TutorialChapter chapter, TutorialLesson? lesson})>[
      for (final chapter in widget.tutorial.chapters)
        if (chapter.lessons.any((lesson) => _matches(chapter, lesson))) ...[
          (chapter: chapter, lesson: null),
          for (final lesson in chapter.lessons)
            if (_matches(chapter, lesson)) (chapter: chapter, lesson: lesson),
        ],
    ];
    final labels = _ContentLabels(context);
    final count = rows.where((row) => row.lesson != null).length;
    return _ContentList.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: rows.isEmpty ? 2 : rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ContentFilterBar(
            selection: _filter,
            languages: [
              for (final lesson in lessons)
                _contentLanguage(lesson.type, lesson.language),
            ],
            levels: [for (final lesson in lessons) lesson.level],
            resultLabel: labels.lessonCount(count),
            onChanged: () => setState(() {}),
          );
        }
        if (rows.isEmpty) return _emptyResults(context);
        final row = rows[index - 1];
        final lesson = row.lesson;
        if (lesson == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              row.chapter.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
        }
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.menu_book_outlined),
          title: _ContentTitle(
            title: lesson.title,
            language: _contentLanguage(lesson.type, lesson.language),
          ),
          subtitle: Text(
            lesson.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _LessonPage(
                lesson: lesson,
                store: widget.store,
                auth: widget.auth,
                settings: widget.settings,
              ),
            ),
          ),
        );
      },
    );
  }

  bool _matches(TutorialChapter chapter, TutorialLesson lesson) =>
      _filter.matches(
        language: _contentLanguage(lesson.type, lesson.language),
        level: lesson.level,
        text:
            '${chapter.title} ${lesson.title} ${lesson.summary} '
            '${lesson.concepts.join(' ')}',
      );
}

class _ExampleCodeList extends StatefulWidget {
  const _ExampleCodeList({
    required this.items,
    this.store,
    this.auth,
    this.settings,
    this.examples,
  });

  final List<ExampleCode> items;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;
  final ExampleCodeStore? examples;

  @override
  State<_ExampleCodeList> createState() => _ExampleCodeListState();
}

class _ExampleCodeListState extends State<_ExampleCodeList> {
  final _filter = _ContentFilterSelection();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    final items = widget.items
        .where(
          (example) => _filter.matches(
            language: _contentLanguage(example.type, example.language),
            level: example.level,
            text:
                '${example.title} ${example.summary} ${example.concepts.join(' ')}',
          ),
        )
        .toList(growable: false);
    return _ContentList.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      itemCount: items.isEmpty ? 2 : items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ContentFilterBar(
            selection: _filter,
            languages: [
              for (final example in widget.items)
                _contentLanguage(example.type, example.language),
            ],
            levels: [for (final example in widget.items) example.level],
            resultLabel: l10n.examplesCount(items.length),
            onChanged: () => setState(() {}),
          );
        }
        if (items.isEmpty) return _emptyResults(context);
        final example = items[index - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.code_outlined),
          title: _ContentTitle(
            title: example.title,
            language: _contentLanguage(example.type, example.language),
          ),
          subtitle: Text(
            example.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExampleDetailPage(
                example: example,
                store: widget.store,
                auth: widget.auth,
                settings: widget.settings,
                examples: widget.examples,
              ),
            ),
          ),
        );
      },
    );
  }
}

String _contentLanguage(String type, String language) =>
    languageKey(language.trim().isEmpty ? type : language);

class _ContentFilterSelection {
  final query = TextEditingController();
  String? language;
  String? level;

  bool get active => query.text.isNotEmpty || language != null || level != null;

  bool matches({
    required String language,
    required String level,
    required String text,
  }) {
    if (this.language != null && this.language != language) return false;
    if (this.level != null && this.level != level.trim().toLowerCase()) {
      return false;
    }
    final words = query.text.trim().toLowerCase().split(RegExp(r'\s+'));
    final searchable = '$text ${languageLabel(language)}'.toLowerCase();
    return words.every(searchable.contains);
  }

  void reset() {
    query.clear();
    language = null;
    level = null;
  }

  void dispose() => query.dispose();
}

class _ContentFilterBar extends StatelessWidget {
  const _ContentFilterBar({
    required this.selection,
    required this.languages,
    required this.levels,
    required this.resultLabel,
    required this.onChanged,
  });

  final _ContentFilterSelection selection;
  final List<String> languages;
  final List<String> levels;
  final String resultLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = _ContentLabels(context);
    final languageChoices = languages
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final levelChoices = levels
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('content-query'),
            controller: selection.query,
            onChanged: (_) => onChanged(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: labels.search,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: selection.query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: labels.clear,
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        selection.query.clear();
                        onChanged();
                      },
                    ),
            ),
          ),
          if (languageChoices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const ValueKey('content-language-all'),
                  label: Text(StudioLocalizations.of(context).allLanguages),
                  selected: selection.language == null,
                  onSelected: (_) {
                    selection.language = null;
                    onChanged();
                  },
                ),
                for (final language in languageChoices)
                  ChoiceChip(
                    key: ValueKey('content-language-$language'),
                    label: Text(languageLabel(language)),
                    selected: selection.language == language,
                    onSelected: (_) {
                      selection.language = language;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          if (levelChoices.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const ValueKey('content-level-all'),
                  label: Text(labels.allLevels),
                  selected: selection.level == null,
                  onSelected: (_) {
                    selection.level = null;
                    onChanged();
                  },
                ),
                for (final level in levelChoices)
                  ChoiceChip(
                    key: ValueKey('content-level-$level'),
                    label: Text(labels.level(level)),
                    selected: selection.level == level,
                    onSelected: (_) {
                      selection.level = level;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(resultLabel, style: Theme.of(context).textTheme.bodyMedium),
              if (selection.active)
                TextButton.icon(
                  key: const ValueKey('content-reset'),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(labels.reset),
                  onPressed: () {
                    selection.reset();
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _emptyResults(BuildContext context) => Padding(
  key: const ValueKey('content-no-results'),
  padding: const EdgeInsets.all(24),
  child: Text(_ContentLabels(context).noResults, textAlign: TextAlign.center),
);

class _ContentTitle extends StatelessWidget {
  const _ContentTitle({required this.title, required this.language});

  final String title;
  final String language;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (language.isNotEmpty) ...[
        LanguageBadge(language: language),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class _ContentLabels {
  _ContentLabels(BuildContext context)
    : chinese = Localizations.localeOf(context).languageCode == 'zh';

  final bool chinese;
  String get search =>
      chinese ? '搜索标题、简介或知识点' : 'Search titles, summaries or concepts';
  String get clear => chinese ? '清除搜索' : 'Clear search';
  String get allLevels => chinese ? '全部难度' : 'All levels';
  String get reset => chinese ? '重置筛选' : 'Reset filters';
  String get noResults => chinese
      ? '没有符合条件的内容，请调整或重置筛选。'
      : 'No matching content. Adjust or reset the filters.';
  String lessonCount(int count) => chinese ? '共 $count 课' : '$count lessons';
  String level(String level) => switch (level) {
    'beginner' => chinese ? '入门' : 'Beginner',
    'intermediate' => chinese ? '进阶' : 'Intermediate',
    'advanced' => chinese ? '高级' : 'Advanced',
    _ => level,
  };
}

class ExampleDetailPage extends StatefulWidget {
  const ExampleDetailPage({
    super.key,
    required this.example,
    this.store,
    this.auth,
    this.settings,
    this.examples,
  });

  final ExampleCode example;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;
  final ExampleCodeStore? examples;

  @override
  State<ExampleDetailPage> createState() => _ExampleDetailPageState();
}

class _ExampleDetailPageState extends State<ExampleDetailPage> {
  late final TextEditingController _code;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.examples?.items.firstWhere(
      (example) => example.id == widget.example.id,
      orElse: () => widget.example,
    );
    _code = TextEditingController(text: saved?.code ?? widget.example.code);
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _ContentTitle(
          title: widget.example.title,
          language: _contentLanguage(
            widget.example.type,
            widget.example.language,
          ),
        ),
      ),
      body: _ContentList(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(widget.example.summary),
          const SizedBox(height: 16),
          CodeSnippet(
            example: widget.example,
            controller: _code,
            store: widget.store,
            auth: widget.auth,
            settings: widget.settings,
          ),
          const SizedBox(height: 16),
          Text(l10n.expectedOutput),
          const SizedBox(height: 6),
          SelectableText(widget.example.output),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.filledTonal(
                tooltip: l10n.restoreDefault,
                onPressed: _saving ? null : _reset,
                icon: const Icon(Icons.restore),
              ),
              IconButton.filledTonal(
                tooltip: l10n.saveExample,
                onPressed: widget.examples == null || _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _reset() => setState(
    () => _code.text =
        widget.examples?.bundledExample(widget.example.id)?.code ??
        widget.example.code,
  );

  Future<void> _save() async {
    final store = widget.examples;
    if (_saving || store == null) return;
    final example = widget.example.copyWith(code: _code.text);
    setState(() => _saving = true);
    try {
      await store.upsert(example);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(StudioLocalizations.of(context).exampleSaved)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LessonPage extends StatelessWidget {
  const _LessonPage({
    required this.lesson,
    this.store,
    this.auth,
    this.settings,
  });

  final TutorialLesson lesson;
  final ProjectStore? store;
  final AuthStore? auth;
  final SettingsStore? settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = StudioLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _ContentTitle(
          title: lesson.title,
          language: _contentLanguage(lesson.type, lesson.language),
        ),
      ),
      body: _ContentList(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(lesson.summary, style: theme.textTheme.titleMedium),
          if (lesson.objective.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l10n.objective, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(lesson.objective),
          ],
          if (lesson.prerequisites.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l10n.prerequisites, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final item in lesson.prerequisites) _BulletLine(text: item),
          ],
          const SizedBox(height: 12),
          Text(lesson.explain),
          const SizedBox(height: 20),
          Text(l10n.sampleCode, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          CodeSnippet(
            example: ExampleCode(
              id: lesson.id,
              type: lesson.type,
              language: lesson.language,
              level: lesson.level,
              title: lesson.title,
              summary: lesson.summary,
              code: lesson.code,
              output: lesson.output,
              sourceLessonId: lesson.id,
              concepts: lesson.concepts,
              inputFixtures: lesson.inputFixtures,
            ),
            store: store,
            auth: auth,
            settings: settings,
          ),
          const SizedBox(height: 16),
          Text(l10n.expectedOutput, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(lesson.output),
          if (lesson.pitfalls.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(l10n.pitfalls, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final item in lesson.pitfalls)
              _BulletLine(text: item, error: true),
          ],
          if (lesson.tasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(l10n.practice, style: theme.textTheme.titleMedium),
            for (final task in lesson.tasks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(task.prompt),
                subtitle: Text(
                  '${l10n.hint(task.hint)}\n${l10n.reference(task.answer)}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// A single bulleted line used for prerequisites and pitfalls.
class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Icon(
              error ? Icons.warning_amber_outlined : Icons.check_circle_outline,
              size: 16,
              color: error
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ContentList extends StatelessWidget {
  const _ContentList({required this.padding, required this.children})
    : itemCount = null,
      itemBuilder = null;

  const _ContentList.builder({
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
  }) : children = null;

  final EdgeInsetsGeometry padding;
  final List<Widget>? children;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: itemBuilder == null
          ? ListView(padding: padding, children: children!)
          : ListView.builder(
              padding: padding,
              itemCount: itemCount,
              itemBuilder: itemBuilder!,
            ),
    ),
  );
}

class _LocalContentError extends StatelessWidget {
  const _LocalContentError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

String _displayName(String language) {
  final profile = StudioProfile.current;
  if (profile?.isOffline == true) {
    return profile!.appTitle;
  }
  final product = StudioProductCatalog.forLanguage(language);
  return product == StudioProductCatalog.qfliStudio
      ? language.toUpperCase()
      : product;
}
