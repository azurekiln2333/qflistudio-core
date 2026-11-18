import 'dart:async';

import 'package:flutter/material.dart';

import '../tool_state_store.dart';
import 'models.dart';
import 'netrix_common.dart';
import 'netrix_localizations.dart';

class NetrixToolPage extends StatefulWidget {
  const NetrixToolPage({
    super.key,
    required this.tool,
    required this.store,
  });

  final ToolDefinition tool;
  final ToolStateStore store;

  @override
  State<NetrixToolPage> createState() => _NetrixToolPageState();
}

class _NetrixToolPageState extends State<NetrixToolPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  ToolResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controllers = <String, TextEditingController>{
      for (final ToolField field in widget.tool.fields)
        field.id: TextEditingController(text: field.initialValue),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_recordRecent());
    });
  }

  Future<void> _recordRecent() async {
    await widget.store.recordRecent(widget.tool.id);
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final ToolResult result = await widget.tool.run(<String, String>{
        for (final MapEntry<String, TextEditingController> entry
            in _controllers.entries)
          entry.key: entry.value.text,
      });
      if (mounted) setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) {
        final NetrixLocalizations strings = NetrixLocalizations.of(context);
        setState(
          () => _result = ToolResult.failure(
            widget.tool.title,
            error,
            localizedMessage: strings.errorMessage(error),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final NetrixLocalizations strings = NetrixLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tool.title),
        actions: <Widget>[
          ListenableBuilder(
            listenable: widget.store,
            builder: (BuildContext context, Widget? child) {
              final bool isFavorite = widget.store.favorites.contains(
                widget.tool.id,
              );
              return IconButton(
                tooltip:
                    isFavorite ? strings.removeFavorite : strings.addFavorite,
                onPressed: () =>
                    unawaited(widget.store.toggleFavorite(widget.tool.id)),
                icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text(
                widget.tool.titleEn,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double horizontal = constraints.maxWidth < 600 ? 16 : 32;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.tool.description,
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: <Widget>[
                          for (final ToolField field
                              in widget.tool.fields) ...<Widget>[
                            _FieldEditor(
                              field: field,
                              controller: _controllers[field.id]!,
                            ),
                            const SizedBox(height: 14),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _running ? null : _run,
                              icon: _running
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.play_arrow_outlined),
                              label: Text(
                                  _running ? strings.running : strings.runTool),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_result != null) ...<Widget>[
                      const SizedBox(height: 24),
                      ToolResultView(result: _result!),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({required this.field, required this.controller});

  final ToolField field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final NetrixLocalizations strings = NetrixLocalizations.of(context);
    if (field.type == ToolFieldType.select) {
      return DropdownButtonFormField<String>(
        initialValue: controller.text.isEmpty
            ? field.options.first
            : controller.text,
        decoration: InputDecoration(labelText: field.label),
        items: field.options
            .map((String option) =>
                DropdownMenuItem(value: option, child: Text(option)))
            .toList(),
        onChanged: (String? value) => controller.text = value ?? '',
        validator: field.required
            ? (String? value) => value == null || value.isEmpty
                ? strings.selectOption(field.label)
                : null
            : null,
      );
    }
    return TextFormField(
      controller: controller,
      minLines: field.type == ToolFieldType.multiline ? 4 : 1,
      maxLines: field.type == ToolFieldType.multiline ? 10 : 1,
      keyboardType: field.keyboardType,
      obscureText: field.obscureText,
      decoration: InputDecoration(labelText: field.label, hintText: field.hint),
      validator: field.required
          ? (String? value) => value == null || value.trim().isEmpty
              ? strings.requiredField(field.label)
              : null
          : null,
    );
  }
}
