import 'package:flutter/material.dart';

import '../focus/focus_sync_state.dart';

class FocusSyncFailureNotice extends StatelessWidget {
  const FocusSyncFailureNotice({super.key, required this.state});

  final FocusSyncState state;

  @override
  Widget build(BuildContext context) {
    if (state.phase != FocusSyncPhase.failed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF173A52),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFB578)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Color(0xFFFFB578)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '部分專注紀錄尚未同步',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.message ?? '目前無法上傳最新紀錄。',
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '連線恢復後會自動重試，也可以重新整理此頁查看最新紀錄。',
                    style: TextStyle(color: Color(0xFFFFD6AF), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
