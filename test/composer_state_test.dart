import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('qfli-composer-'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  FileComposerDefaultsStore store() => FileComposerDefaultsStore(root: dir);

  group('composer state', () {
    test('a fresh composer asks before every write', () {
      final state = ComposerState();
      addTearDown(state.dispose);

      expect(state.permission, AgentPermissionMode.askEveryWrite);
      expect(state.modelId, isNull);
      expect(state.reasoningEffort, isNull);
      expect(state.canSend, isFalse);
    });

    test('text decides whether the card can send', () {
      final state = ComposerState();
      addTearDown(state.dispose);

      state.text = '   ';
      expect(state.canSend, isFalse);
      state.text = '改一下 Main.java';
      expect(state.canSend, isTrue);
    });

    test('attachments alone can send and never duplicate', () {
      final state = ComposerState();
      addTearDown(state.dispose);

      state.attach('src/Main.java');
      state.attach('src/Main.java');
      state.attachAll(['src/Util.java', 'src/Main.java', '  ']);

      expect(state.attachments, ['src/Main.java', 'src/Util.java']);
      expect(state.canSend, isTrue);

      state.detach('src/Main.java');
      expect(state.attachments, ['src/Util.java']);
    });

    test('a project file becomes a relative path with slashes', () {
      final state = ComposerState(projectRoot: '/work/smoke');
      addTearDown(state.dispose);

      // 反斜杠折成正斜杠，保持相对形态。
      expect(state.payloadPath('src\\Main.java'), 'src/Main.java');
      // 项目内的绝对路径折成相对路径：agent 只接受相对路径。
      expect(state.payloadPath('/work/smoke/src/Main.java'), 'src/Main.java');
      expect(
        state.payloadPath('/work/smoke/src/util/Util.java'),
        'src/util/Util.java',
      );
    });

    test('a file outside the project keeps its absolute path', () {
      final state = ComposerState(projectRoot: '/work/smoke');
      addTearDown(state.dispose);

      expect(state.payloadPath('/other/Util.java'), '/other/Util.java');
      // 前缀相似但不是子目录，不能误折。
      expect(
        state.payloadPath('/work/smoke-two/Util.java'),
        '/work/smoke-two/Util.java',
      );
      // 项目根本身是目录，不是附件。
      expect(state.payloadPath('/work/smoke'), '');
    });

    test('without a project root only the separators are normalized', () {
      final state = ComposerState();
      addTearDown(state.dispose);

      expect(state.payloadPath('src\\Main.java'), 'src/Main.java');
      expect(state.payloadPath('/abs/Util.java'), '/abs/Util.java');
    });

    test('attaching normalizes and dedupes on the payload form', () {
      final state = ComposerState(projectRoot: '/work/smoke');
      addTearDown(state.dispose);

      state.attachAll([
        '/work/smoke/src/Main.java',
        'src/Main.java',
        'src\\Util.java',
      ]);

      // 同一文件两种写法只算一个，最终都是相对路径。
      expect(state.attachments, ['src/Main.java', 'src/Util.java']);
    });

    test('changing the model clears a reasoning effort from the old model', () {
      final state = ComposerState();
      addTearDown(state.dispose);

      state.modelId = 'model-a';
      state.reasoningEffort = 'high';
      expect(state.reasoningEffort, 'high');

      state.modelId = 'model-b';
      expect(state.reasoningEffort, isNull);
    });

    test('sending clears input but keeps the permission and model', () {
      final state = ComposerState();
      addTearDown(state.dispose);
      state.text = 'hello';
      state.attach('a.txt');
      state.permission = AgentPermissionMode.autoAcceptEdits;
      state.modelId = 'model-a';

      state.clearInput();

      expect(state.text, isEmpty);
      expect(state.attachments, isEmpty);
      expect(state.permission, AgentPermissionMode.autoAcceptEdits);
      expect(state.modelId, 'model-a');
    });
  });

  group('composer defaults', () {
    test('a project remembers permission, model and effort', () async {
      final first = ComposerState(defaults: store(), projectId: 'project-1');
      await first.bindProject('project-1');
      first.permission = AgentPermissionMode.readOnly;
      first.modelId = 'model-a';
      first.reasoningEffort = 'low';
      await first.flush();
      first.dispose();

      final second = ComposerState(defaults: store(), projectId: 'project-1');
      await second.bindProject('project-1');
      addTearDown(second.dispose);

      expect(second.permission, AgentPermissionMode.readOnly);
      expect(second.modelId, 'model-a');
      expect(second.reasoningEffort, 'low');
    });

    test('another project starts from the default', () async {
      final storeFile = store();
      await storeFile.write(
        'project-1',
        const ComposerDefaults(permission: AgentPermissionMode.readOnly),
      );

      final state = ComposerState(defaults: storeFile, projectId: 'project-2');
      await state.bindProject('project-2');
      addTearDown(state.dispose);

      expect(state.permission, AgentPermissionMode.askEveryWrite);
    });

    test('a broken defaults file reads as unset instead of failing', () async {
      File(
        p.join(dir.path, FileComposerDefaultsStore.fileName),
      ).writeAsStringSync('{not json');

      final state = ComposerState(defaults: store(), projectId: 'project-1');
      await state.bindProject('project-1');
      addTearDown(state.dispose);

      expect(state.permission, AgentPermissionMode.askEveryWrite);
      expect(state.modelId, isNull);
    });

    test('an unknown permission name falls back per field', () async {
      File(
        p.join(dir.path, FileComposerDefaultsStore.fileName),
      ).writeAsStringSync(
        jsonEncode({
          'project-1': {'permission': 'nonsense', 'modelId': 'kept'},
        }),
      );

      final state = ComposerState(defaults: store(), projectId: 'project-1');
      await state.bindProject('project-1');
      addTearDown(state.dispose);

      expect(state.permission, AgentPermissionMode.askEveryWrite);
      expect(state.modelId, 'kept');
    });
  });
}
