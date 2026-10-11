/// 社区数据模型（与 azurekiln-qfli-server 的 JSON 契约对应）。
class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.bio,
    required this.avatarColor,
    required this.points,
    required this.checkinStreak,
    required this.provider,
    this.isAdmin = false,
    this.gatewayUserId,
    this.avatarUrl = '',
    this.growth = const UserGrowth(),
  });

  final String id;
  final String? gatewayUserId;
  final bool isAdmin;
  final String username;
  final String nickname;
  final String bio;
  final String avatarColor;
  final String avatarUrl;
  final int points;
  final int checkinStreak;
  final String provider;
  final UserGrowth growth;

  static CommunityUser fromJson(Map<String, dynamic> j) => CommunityUser(
    id: j['id'].toString(),
    gatewayUserId: j['gatewayUserId'] as String?,
    username: j['username'] as String? ?? '',
    nickname: j['nickname'] as String? ?? '',
    bio: j['bio'] as String? ?? '',
    avatarColor: j['avatarColor'] as String? ?? '#2196F3',
    avatarUrl: j['avatarUrl'] as String? ?? '',
    points: (j['points'] as num?)?.toInt() ?? 0,
    checkinStreak: (j['checkinStreak'] as num?)?.toInt() ?? 0,
    provider: j['provider'] as String? ?? 'local',
    isAdmin: j['isAdmin'] as bool? ?? false,
    growth: UserGrowth.fromJson(
      j['growth'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

class UserGrowth {
  const UserGrowth({
    this.experience = 0,
    this.level = 1,
    this.levelExperience = 0,
    this.requiredExperience = 100,
  });

  final int experience;
  final int level;
  final int levelExperience;
  final int requiredExperience;

  double get progress => requiredExperience > 0
      ? (levelExperience / requiredExperience).clamp(0.0, 1.0)
      : 0;

  static UserGrowth fromJson(Map<String, dynamic> json) => UserGrowth(
    experience: (json['experience'] as num?)?.toInt() ?? 0,
    level: (json['level'] as num?)?.toInt() ?? 1,
    levelExperience: (json['levelExperience'] as num?)?.toInt() ?? 0,
    requiredExperience: (json['requiredExperience'] as num?)?.toInt() ?? 100,
  );

  Map<String, dynamic> toJson() => {
    'experience': experience,
    'level': level,
    'levelExperience': levelExperience,
    'requiredExperience': requiredExperience,
  };
}

class Zone {
  const Zone({required this.id, required this.key, required this.name});

  final String id;
  final String key;
  final String name;

  static Zone fromJson(Map<String, dynamic> j) => Zone(
    id: j['id'] as String,
    key: j['key'] as String,
    name: j['name'] as String,
  );
}

class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.nickname,
    required this.username,
    required this.avatarColor,
  });

  final String id;
  final String nickname;
  final String username;
  final String avatarColor;

  static PostAuthor fromJson(Map<String, dynamic> j) => PostAuthor(
    id: j['id'].toString(),
    nickname: j['nickname'] as String? ?? '',
    username: j['username'] as String? ?? '',
    avatarColor: j['avatarColor'] as String? ?? '#2196F3',
  );
}

class Post {
  const Post({
    required this.id,
    required this.type,
    required this.title,
    required this.excerpt,
    required this.content,
    required this.tags,
    required this.zoneId,
    required this.zoneName,
    required this.author,
    required this.likeCount,
    required this.commentCount,
    required this.liked,
    required this.createdAt,
  });

  final String id;
  final String type; // tutorial | discussion
  final String title;
  final String excerpt;
  final String content;
  final List<String> tags;
  final String zoneId;
  final String zoneName;
  final PostAuthor author;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final String createdAt;

  static Post fromJson(Map<String, dynamic> j) => Post(
    id: j['id'] as String,
    type: j['type'] as String,
    title: j['title'] as String? ?? '',
    excerpt: j['excerpt'] as String? ?? '',
    content: j['content'] as String? ?? j['excerpt'] as String? ?? '',
    tags: [for (final t in (j['tags'] as List? ?? [])) t as String],
    zoneId: j['zoneId'] as String? ?? '',
    zoneName: j['zoneName'] as String? ?? '',
    author: PostAuthor.fromJson(j['author'] as Map<String, dynamic>),
    likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
    commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
    liked: j['liked'] as bool? ?? false,
    createdAt: j['createdAt'] as String? ?? '',
  );
}

class Comment {
  const Comment({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.parentId,
    required this.author,
    required this.children,
  });

  final String id;
  final String content;
  final String createdAt;
  final String? parentId;
  final PostAuthor author;
  final List<Comment> children;

  static Comment fromJson(Map<String, dynamic> j) => Comment(
    id: j['id'] as String,
    content: j['content'] as String? ?? '',
    createdAt: j['createdAt'] as String? ?? '',
    parentId: j['parentId'] as String?,
    author: PostAuthor.fromJson(j['author'] as Map<String, dynamic>),
    children: [
      for (final c in (j['children'] as List? ?? []))
        Comment.fromJson(c as Map<String, dynamic>),
    ],
  );
}

class TaskInfo {
  const TaskInfo({
    required this.key,
    required this.eventKey,
    required this.label,
    required this.done,
    required this.reward,
    required this.progress,
    required this.target,
  });

  final String key;
  final String eventKey;
  final String label;
  final bool done;
  final int reward;
  final int progress;
  final int target;

  static TaskInfo fromJson(Map<String, dynamic> j) => TaskInfo(
    key: j['key'] as String,
    eventKey: j['eventKey'] as String? ?? j['key'] as String,
    label: j['label'] as String,
    done: j['done'] as bool? ?? false,
    reward: (j['reward'] as num?)?.toInt() ?? 0,
    progress: (j['progress'] as num?)?.toInt() ?? 0,
    target: (j['target'] as num?)?.toInt() ?? 1,
  );

  Map<String, dynamic> toJson() => {
    'key': key, 'eventKey': eventKey, 'label': label, 'done': done,
    'reward': reward, 'progress': progress, 'target': target,
  };

  TaskInfo withProgress(int value) => TaskInfo(
    key: key, eventKey: eventKey, label: label, done: done,
    reward: reward, progress: value, target: target,
  );
}

class DailyTasksSnapshot {
  const DailyTasksSnapshot({required this.day, required this.checkedToday,
    required this.streak, required this.points, required this.growth,
    required this.tasks});

  final String day;
  final bool checkedToday;
  final int streak;
  final int points;
  final UserGrowth growth;
  final List<TaskInfo> tasks;

  factory DailyTasksSnapshot.fromJson(Map<String, dynamic> data) =>
      DailyTasksSnapshot(
        day: data['day'] as String? ?? '',
        checkedToday: data['checkedToday'] as bool? ?? false,
        streak: (data['streak'] as num?)?.toInt() ?? 0,
        points: (data['points'] as num?)?.toInt() ?? 0,
        growth: UserGrowth.fromJson(
          data['growth'] as Map<String, dynamic>? ?? const {},
        ),
        tasks: [
          for (final row in data['tasks'] as List? ?? const [])
            TaskInfo.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
    'day': day, 'checkedToday': checkedToday, 'streak': streak,
    'points': points, 'growth': growth.toJson(),
    'tasks': [for (final task in tasks) task.toJson()],
  };
}

class TagCount {
  const TagCount({required this.tag, required this.count});

  final String tag;
  final int count;

  static TagCount fromJson(Map<String, dynamic> j) =>
      TagCount(tag: j['tag'] as String, count: (j['count'] as num).toInt());
}
