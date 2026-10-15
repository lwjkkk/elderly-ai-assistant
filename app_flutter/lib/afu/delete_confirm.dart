import 'package:flutter/material.dart';

/// 全局统一的黑白删除确认弹窗。
Future<bool> showDeleteConfirm(BuildContext context, String itemName) async {
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('删除记录',
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
          content: Text('确定删除$itemName吗？删除后无法恢复。',
              style: const TextStyle(
                  color: Colors.black87, fontSize: 18, height: 1.5)),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(c, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black),
              ),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
}
