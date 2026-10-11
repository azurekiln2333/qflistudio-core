import 'package:flutter/material.dart';

import '../editor/editor_fonts.dart';
import '../store/settings_store.dart';
import '../widgets/settings_section.dart';

class EditorFontSettingsPage extends StatefulWidget {
  const EditorFontSettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<EditorFontSettingsPage> createState() => _EditorFontSettingsPageState();
}

class _EditorFontSettingsPageState extends State<EditorFontSettingsPage> {
  late double _size = widget.settings.editorFontSize;
  late double _height = widget.settings.editorLineHeight;

  SettingsStore get settings => widget.settings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('编辑器字体'),
      actions: [
        IconButton(
          tooltip: '恢复默认',
          icon: const Icon(Icons.restore),
          onPressed: () {
            setState(() {
              _size = EditorFonts.defaultSize;
              _height = 1.4;
            });
            settings.setEditorFont(
              font: EditorFonts.defaultFont,
              size: _size,
              height: _height,
              bold: true,
              italic: false,
            );
          },
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              SettingsSection(
                title: '字体',
                children: [
                  RadioGroup<String>(
                    groupValue: settings.editorFont,
                    onChanged: (value) => settings.setEditorFont(font: value),
                    child: Column(
                      children: [
                        for (final font in EditorFonts.choices.entries)
                          RadioListTile<String>(
                            title: Text(font.value),
                            value: font.key,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: '排版',
                children: [
                  ListTile(
                    title: const Text('字号'),
                    trailing: Text(_size.toStringAsFixed(1)),
                  ),
                  Slider(
                    value: _size,
                    min: EditorFonts.minSize,
                    max: EditorFonts.maxSize,
                    divisions: 42,
                    label: _size.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _size = value),
                    onChangeEnd: (value) => settings.setEditorFont(size: value),
                  ),
                  ListTile(
                    title: const Text('行高'),
                    trailing: Text(_height.toStringAsFixed(1)),
                  ),
                  Slider(
                    value: _height,
                    min: 1,
                    max: 2,
                    divisions: 10,
                    label: _height.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _height = value),
                    onChangeEnd: (value) =>
                        settings.setEditorFont(height: value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.format_bold),
                    title: const Text('粗体'),
                    value: settings.editorBold,
                    onChanged: (value) => settings.setEditorFont(bold: value),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.format_italic),
                    title: const Text('斜体'),
                    value: settings.editorItalic,
                    onChanged: (value) => settings.setEditorFont(italic: value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'const answer = 42;\n'
                  'if (answer > 0) {\n'
                  '  print("你好，QFLI");\n'
                  '}\n'
                  '0123456789  () [] {}',
                  style: settings.editorTextStyle.copyWith(
                    fontSize: _size,
                    height: _height,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
