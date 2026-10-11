import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

void main() {
  test(
    'offline task events survive restart and retain their event ID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qfli-task-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final auth = AuthStore(storageFile: File('${directory.path}/auth.json'));
      await auth.load();
      await auth.signIn(
        'test-token',
        const CommunityUser(
          id: 'user_11111111111111111111111111111111',
          username: 'tester',
          nickname: 'Tester',
          bio: '',
          avatarColor: '#2196F3',
          points: 0,
          checkinStreak: 0,
          provider: 'local',
        ),
      );
      final eventIds = <String>[];
      var offline = true;
      final client = ApiClient(
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/me/task-events')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            eventIds.add(body['eventId'] as String);
            if (offline) return http.Response('{"error":"offline"}', 503);
            return http.Response(
              jsonEncode({
                'day': '2026-09-28',
                'points': 10,
                'streak': 0,
                'checkedToday': false,
                'growth': {'experience': 10},
                'reward': 10,
                'duplicate': false,
                'tasks': [
                  {
                    'key': 'create_project',
                    'eventKey': 'create_project',
                    'label': '创建项目',
                    'target': 1,
                    'progress': 1,
                    'reward': 10,
                    'done': true,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{"error":"unexpected request"}', 404);
        }),
      );
      final storage = File('${directory.path}/daily_tasks.json');
      DateTime clock() => DateTime(2026, 9, 28);
      final first = TaskActivityService(
        storageFile: storage,
        client: client,
        clock: clock,
      );
      await first.record(auth, 'create_project');
      await first.syncPending(auth, force: true);
      expect(first.countToday(auth, 'create_project'), 1);
      expect(first.pendingCount(auth), 1);

      offline = false;
      final restored = TaskActivityService(
        storageFile: storage,
        client: client,
        clock: clock,
      );
      await restored.initialize();
      expect(restored.countToday(auth, 'create_project'), 1);
      expect(restored.pendingCount(auth), 1);
      await restored.syncPending(auth, force: true);
      expect(restored.pendingCount(auth), 0);
      expect(restored.snapshotFor(auth)?.tasks.single.done, true);
      expect(auth.user?.points, 10);
      expect(eventIds.toSet().length, 1);
      client.close();
    },
  );
}
