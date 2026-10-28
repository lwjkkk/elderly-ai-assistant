import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:elderly_ai_assistant/services/medication/medication_name.dart';

/// 录入药品共享表单（长辈端提醒用药 / 家属端本人-长辈用药页共用，同排版同配色）。
///
/// 字段：药名 / 剂量 / 频次（滚轮＋手动输入）/ 开始用药日期（中文年月日滚轮）/ 用药时间点（多选）。
/// 返回 null 表示取消；否则返回 {name, dosage, frequency, times, startDate}，
/// 调用方自行提交接口（开始日期后端暂无字段，仅界面采集）。

Future<Map<String, dynamic>?> showMedFormDialog(BuildContext context,
    {String? presetName,
    String? presetDose,
    String? presetFreq,
    List<String>? presetTimes,
    String? autoNote}) async {
  final nameC =
      TextEditingController(text: medicationChineseName(presetName ?? ''));
  final doseC = TextEditingController(text: presetDose ?? '');
  const freqOptions = ['每日一次', '每日两次', '每日三次', '隔日一次', '手动输入'];
  final freqManualC = TextEditingController(
      text: (presetFreq ?? '').isNotEmpty && !freqOptions.contains(presetFreq)
          ? presetFreq!
          : '');
  final initialFreq = (presetFreq ?? '').trim();
  var freq = initialFreq.isEmpty
      ? '每日两次'
      : freqOptions.contains(initialFreq)
          ? initialFreq
          : '手动输入';
  var start = DateTime.now();
  final times = <String>[];
  List<String> suggestedTimes(String selected) {
    final normalized = selected
        .replaceAll('两', '2')
        .replaceAll('二', '2')
        .replaceAll('三', '3')
        .replaceAll('四', '4')
        .replaceAll('一', '1');
    final count =
        int.tryParse(RegExp(r'(\d+)次').firstMatch(normalized)?.group(1) ?? '');
    if (count == 3) return ['08:00', '13:00', '19:00'];
    if (count == 2) return ['08:00', '20:00'];
    if (count == 1) return ['08:00'];
    if (count != null && count > 3 && count <= 12) {
      return List.generate(count, (i) {
        final minute = 8 * 60 + (12 * 60 * i / (count - 1)).round();
        return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
      });
    }
    return times.isEmpty ? ['08:00'] : List<String>.from(times);
  }

  times.addAll((presetTimes ?? []).isNotEmpty
      ? presetTimes!
      : suggestedTimes(initialFreq.isEmpty ? freq : initialFreq));
  String fmtD(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String fmtT(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  InputDecoration boxDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 20, color: Color(0xFF6B7280)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFD8E6F3))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFD8E6F3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF345C87), width: 2)),
      );

  Widget formRow(String label, String? sub, Widget field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 128,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF212936))),
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFF6B7280), height: 1.4)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: field),
      ]),
    );
  }

  Widget pickBox(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E6F3)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 20, color: Color(0xFF212936))),
          ),
          const Icon(Icons.arrow_drop_down, size: 28, color: Color(0xFF345C87)),
        ]),
      ),
    );
  }

  Future<void> sheet(
      StateSetter setD, String title, Widget body, VoidCallback onOk) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('取消',
                    style: TextStyle(fontSize: 19, color: Color(0xFF6B7280))),
              ),
              Expanded(
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212936))),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  onOk();
                },
                child: const Text('确定',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF345C87))),
              ),
            ]),
          ),
          SizedBox(height: 220, child: body),
        ]),
      ),
    );
  }

  Future<void> pickFreq(StateSetter setD) async {
    var tmp = freqOptions.indexOf(freq);
    if (tmp < 0) tmp = 1;
    var cur = tmp;
    await sheet(
        setD,
        '选择频次',
        CupertinoPicker(
          itemExtent: 46,
          scrollController: FixedExtentScrollController(initialItem: tmp),
          onSelectedItemChanged: (v) => cur = v,
          children: [
            for (final o in freqOptions)
              Center(child: Text(o, style: const TextStyle(fontSize: 21))),
          ],
        ),
        () => setD(() {
              freq = freqOptions[cur];
              if (freq != '手动输入') {
                times
                  ..clear()
                  ..addAll(suggestedTimes(freq));
              }
            }));
  }

  Future<void> pickDate(StateSetter setD) async {
    var y = start.year, m = start.month, d = start.day;
    int maxD() => DateTime(y, m + 1, 0).day;
    if (d > maxD()) d = maxD();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => StatefulBuilder(
        builder: (c, setP) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('取消',
                      style: TextStyle(fontSize: 19, color: Color(0xFF6B7280))),
                ),
                const Expanded(
                  child: Text('选择日期',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF212936))),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    setD(() => start = DateTime(y, m, d));
                  },
                  child: const Text('确定',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF345C87))),
                ),
              ]),
            ),
            SizedBox(
              height: 220,
              child: Row(children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 46,
                    scrollController:
                        FixedExtentScrollController(initialItem: y - 2020),
                    onSelectedItemChanged: (v) => setP(() {
                      y = 2020 + v;
                      if (d > maxD()) d = maxD();
                    }),
                    children: [
                      for (var yy = 2020; yy <= 2035; yy++)
                        Center(
                            child: Text('$yy年',
                                style: const TextStyle(fontSize: 21))),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 46,
                    scrollController:
                        FixedExtentScrollController(initialItem: m - 1),
                    onSelectedItemChanged: (v) => setP(() {
                      m = v + 1;
                      if (d > maxD()) d = maxD();
                    }),
                    children: [
                      for (var mm = 1; mm <= 12; mm++)
                        Center(
                            child: Text('$mm月',
                                style: const TextStyle(fontSize: 21))),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    key: ValueKey(maxD()),
                    itemExtent: 46,
                    scrollController:
                        FixedExtentScrollController(initialItem: d - 1),
                    onSelectedItemChanged: (v) => setP(() => d = v + 1),
                    children: [
                      for (var dd = 1; dd <= maxD(); dd++)
                        Center(
                            child: Text('$dd日',
                                style: const TextStyle(fontSize: 21))),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> pickTime(StateSetter setD) async {
    final now = DateTime.now();
    var cur = DateTime(now.year, now.month, now.day, 8, 0);
    await sheet(
        setD,
        '选择时间',
        CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: true,
          initialDateTime: cur,
          onDateTimeChanged: (v) => cur = v,
        ),
        () => setD(() {
              final s = fmtT(cur);
              if (!times.contains(s)) times.add(s);
            }));
  }

  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black45,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => Dialog(
        backgroundColor: const Color(0xFFF4F5F7),
        insetPadding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 38, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('录入药品',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF212936))),
            if (autoNote != null) ...[
              const SizedBox(height: 8),
              Text(autoNote,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 18, color: Color(0xFF345C87))),
            ],
            const SizedBox(height: 20),
            formRow(
                '药名',
                null,
                TextField(
                  controller: nameC,
                  cursorColor: const Color(0xFF345C87),
                  style:
                      const TextStyle(fontSize: 20, color: Color(0xFF212936)),
                  decoration: boxDec('在此输入'),
                )),
            formRow(
                '剂量',
                '示例：20毫克 或 一片一次',
                TextField(
                  controller: doseC,
                  cursorColor: const Color(0xFF345C87),
                  style:
                      const TextStyle(fontSize: 20, color: Color(0xFF212936)),
                  decoration: boxDec('在此输入'),
                )),
            formRow(
                '频次',
                '示例：每日两次',
                freq == '手动输入'
                    ? TextField(
                        controller: freqManualC,
                        onChanged: (value) => setD(() {
                          final suggested = suggestedTimes(value);
                          times
                            ..clear()
                            ..addAll(suggested);
                        }),
                        cursorColor: const Color(0xFF345C87),
                        style: const TextStyle(
                            fontSize: 20, color: Color(0xFF212936)),
                        decoration: boxDec('在此输入'),
                      )
                    : pickBox(freq, () => pickFreq(setD))),
            formRow(
                '开始使用\n药品日期', null, pickBox(fmtD(start), () => pickDate(setD))),
            formRow(
                '用药时间点',
                '可添加多个时间',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in times)
                        Container(
                          padding: const EdgeInsets.only(
                              left: 14, right: 6, top: 8, bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF4FB),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(s,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF345C87))),
                            GestureDetector(
                              onTap: () => setD(() => times.remove(s)),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close,
                                    size: 18, color: Color(0xFF345C87)),
                              ),
                            ),
                          ]),
                        ),
                      GestureDetector(
                        onTap: () => pickTime(setD),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF345C87)),
                          ),
                          child: const Text('+添加时间',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF345C87))),
                        ),
                      ),
                    ],
                  ),
                ])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('取消',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF555555))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF345C87),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('保存',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return null;
  if (nameC.text.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入药名')));
    }
    return null;
  }
  return <String, dynamic>{
    'name': nameC.text.trim(),
    'dosage': doseC.text.trim(),
    'frequency': freq == '手动输入'
        ? (freqManualC.text.trim().isEmpty ? '手动输入' : freqManualC.text.trim())
        : freq,
    'times': List<String>.from(times),
    'startDate': fmtD(start),
  };
}
