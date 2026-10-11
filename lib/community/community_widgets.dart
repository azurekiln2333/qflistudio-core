import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../community/models.dart';
import '../services/avatar_cache.dart';

/// 网关头像加载失败时使用昵称首字母。
class Avatar extends StatefulWidget {
  const Avatar({
    super.key,
    required this.name,
    this.color,
    this.imageUrl = '',
    this.size = 40,
    required this.cacheKey,
    this.refreshToken = 0,
  });

  final String name;
  final String? color;
  final String imageUrl;
  final double size;
  final String cacheKey;
  final int refreshToken;

  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> {
  File? _image;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedAccount = oldWidget.cacheKey != widget.cacheKey;
    if (changedAccount || widget.imageUrl.trim().isEmpty) _image = null;
    if (changedAccount ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.refreshToken != widget.refreshToken) {
      _load(recheck: oldWidget.refreshToken != widget.refreshToken);
    }
  }

  Future<void> _load({bool recheck = false}) async {
    final request = ++_request;
    final url = widget.imageUrl.trim();
    if (url.isEmpty) return;
    final image = await AvatarCache.resolve(
      widget.cacheKey,
      url,
      recheck: recheck,
    );
    if (!mounted || request != _request || image == null) return;
    var failed = false;
    await precacheImage(
      FileImage(image),
      context,
      onError: (_, _) => failed = true,
    );
    if (!mounted || request != _request || failed) return;
    if (_image?.path != image.path) setState(() => _image = image);
  }

  Color get _bg {
    final hex = (widget.color ?? '#2196F3').replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16) ?? 0x2196F3;
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim().characters.first;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _bg),
      alignment: Alignment.center,
      child: ClipOval(
        child: _image == null
            ? _initial(initial)
            : Image.file(
                _image!,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, synchronous) =>
                    synchronous || frame != null ? child : _initial(initial),
                errorBuilder: (context, error, stackTrace) => _initial(initial),
              ),
      ),
    );
  }

  Widget _initial(String initial) => Center(
    child: Text(
      initial.toUpperCase(),
      style: TextStyle(
        color: Colors.white,
        fontSize: widget.size * 0.42,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 标签 chip（#xxx）。
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.tag, this.onTap});

  final String tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '#$tag',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

/// 帖子卡片（教程/讨论列表共用）。
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.onOpen});

  final Post post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTutorial = post.type == 'tutorial';
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isTutorial
                          ? scheme.primaryContainer
                          : scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isTutorial ? '教程' : '讨论',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isTutorial
                            ? scheme.onPrimaryContainer
                            : scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      post.zoneName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                post.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post.author.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Icon(
                    Icons.favorite,
                    size: 14,
                    color: post.liked
                        ? scheme.error
                        : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likeCount}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentCount}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 评论树（含嵌套回复），回调 [onReply] 携带被回复的评论 id。
class CommentTree extends StatelessWidget {
  const CommentTree({
    super.key,
    required this.comments,
    required this.onReply,
    this.currentUserId,
  });

  final List<Comment> comments;
  final ValueChanged<Comment> onReply;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '还没有评论，来抢沙发',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final c in comments)
          _CommentNode(
            comment: c,
            onReply: onReply,
            currentUserId: currentUserId,
            depth: 0,
          ),
      ],
    );
  }
}

class _CommentNode extends StatelessWidget {
  const _CommentNode({
    required this.comment,
    required this.onReply,
    required this.currentUserId,
    required this.depth,
  });

  final Comment comment;
  final ValueChanged<Comment> onReply;
  final String? currentUserId;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: depth > 0 ? 20.0 : 0, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comment.author.nickname,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (currentUserId == comment.author.id)
                          Text(
                            '（我）',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    Text(
                      comment.content,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Row(
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 28),
                          ),
                          onPressed: () => onReply(comment),
                          child: const Text('回复'),
                        ),
                        Text(
                          comment.createdAt,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.children.isNotEmpty)
            for (final child in comment.children)
              _CommentNode(
                comment: child,
                onReply: onReply,
                currentUserId: currentUserId,
                depth: depth + 1,
              ),
        ],
      ),
    );
  }
}

/// 把服务端时间（UTC "YYYY-MM-DD HH:MM:SS"）转成相对时间。
String relativeTime(String raw) {
  final parsed = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
  if (parsed == null) return raw;
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return raw.split(' ').first;
}

/// 复制文本并提示。
void copyWithToast(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '已复制：${text.length > 40 ? '${text.substring(0, 40)}…' : text}',
      ),
    ),
  );
}
