import 'package:flutter/material.dart';
import '../services/api.dart';
import 'delete_confirm.dart';

class UploadedAvatarActions extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onDeleted;
  const UploadedAvatarActions({super.key, required this.child, required this.onDeleted});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () async {
      try {
        final profile = await ApiService.getProfile();
        if (!context.mounted) return;
        if ((profile['avatar_url'] ?? '').toString().isEmpty) return;
        if (!await showDeleteConfirm(context, '当前上传的头像')) return;
        await ApiService.deleteAvatar();
        await onDeleted();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('头像删除失败：${ApiService.friendly(e)}')));
      }
    },
    child: child,
  );
}
