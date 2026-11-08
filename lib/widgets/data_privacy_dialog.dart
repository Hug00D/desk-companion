import 'package:flutter/material.dart';

Future<void> showDataPrivacyDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: const Color(0x660A1728),
  builder: (_) => const DataPrivacyDialog(),
);

class DataPrivacyDialog extends StatelessWidget {
  const DataPrivacyDialog({super.key});

  static const sections = <(String, String)>[
    (
      '相機與偵測',
      '相機畫面在裝置上分析，用來估計眼睛、頭部、姿勢與是否在座。一般偵測流程不會上傳原始畫面；偵測狀態與部分數值會隨事件紀錄傳送至後端。使用測試影片時，主畫面會標示來源。',
    ),
    (
      '麥克風與語音辨識',
      '開啟喚醒詞時，只在主畫面前景聆聽；切換頁面或進入背景後暫停。喚醒詞在裝置上辨識；語音轉文字由裝置的語音服務處理，可能依系統與可用模型連線。',
    ),
    (
      '辨識文字與 AI 回答',
      '你輸入或辨識出的文字、相關對話內容，以及計時與狀態摘要，會在使用 AI 互動時傳送至後端，用於理解指令與產生回答。啟用語音回覆時，回答文字也會交由語音服務產生音訊，因此這些功能可能需要網路。',
    ),
    (
      '專注與事件紀錄',
      '登入後，專注時長、計時狀態與偵測事件會傳送至後端，供紀錄與統計使用。語音事件也可能包含辨識文字、指令與時間。安靜模式仍會偵測與記錄，也不會關閉已啟用的自動暫停。',
    ),
    (
      '本機報告與偏好',
      '每輪評分會依帳號保存在此裝置，訪客紀錄分開保存。重開 App 仍可查看，但不會跨手機同步；移除 App 或清除資料會刪除本機報告。安靜模式、AI 語氣與語音回覆選擇也保存在本機。關閉語音回覆不會一併關閉喚醒詞。',
    ),
    (
      '保存與同步限制',
      '尚未同步的專注資料只暫存在本次執行期間，關閉 App 或被系統結束後可能遺失；看到本機報告不代表後端同步成功。伺服器紀錄、日誌與回覆音檔由專題部署環境管理，如需確認保存或處理方式，請聯絡專題團隊。本版本尚未提供資料匯出或完整刪除介面。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xF2193B52),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x40FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        key: const ValueKey('data-privacy-card'),
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.76,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.privacy_tip_outlined,
                    color: Color(0xFF9FF3D0),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '資料與隱私',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '關閉資料與隱私',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x26FFFFFF)),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('data-privacy-content'),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '了解展示版本如何使用、傳送與保存資料。',
                      style: TextStyle(color: Color(0xCCFFFFFF), height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    for (final (title, body) in sections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              body,
                              style: const TextStyle(
                                color: Color(0xDDFFFFFF),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0x26FFFFFF)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9FF3D0),
                    foregroundColor: const Color(0xFF17334B),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('關閉'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
