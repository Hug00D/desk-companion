# 雙軌任務 0＋任務 1 Review

- 日期：2026-10-02
- Branch：`feature/vision-lab-dual-track`
- 起點：`8cd0c0e`，已 fetch 並確認與 `origin/codex/vision-lab-v2-pose-context` 一致。
- 本輪修改尚未 commit／push。
- 狀態：任務 0 完成；任務 1 工具與工程測試完成，真實 test6 CSV 驗收待補。停在 Review。
- 正式 App：本輪未接入雙軌，也未改正式 detector／evaluator 的行為。

## 修改檔案

| 檔案 | 用途 |
| --- | --- |
| `lib/vision/dual_track_context_classifier.dart` | 純 Dart、可 reset 的慢軌與仲裁器 |
| `lib/vision/vision_lab_replay.dart` | 從原 replay 抽出的 CSV 解析與正式 evaluator 回放 |
| `lib/vision/dual_track_lab_report.dart` | 逐幀、事件、unknown 與閱讀誤報指標 |
| `tool/vision_lab_dual_track.dart` | 2 秒／3 秒 CLI，產生三種 CSV |
| `tool/vision_lab_replay_companion.dart` | 改用共用 helper，保留原輸出格式與指標 |
| `test/vision/dual_track_context_classifier_test.dart` | 26 項新增測試 |
| `test/fixtures/vision/dual_track_*.csv` | 合成特徵、合成 GT、重構前凍結的正式 replay |
| `docs/vision-lab-test-log.md` | 附加本輪工程驗證紀錄 |

進場前已有 `lib/api/assistant_api.dart`、`lib/screens/face_detection_screen.dart`、
`pubspec.yaml`、`pubspec.lock`、`steps/local_server_steps` 的未提交修改；這些不屬於本輪交付。

## 初始規則與待 Review 的參數

以下是任務 1 的可解釋起始規則，尚未用 test6～test9 調參或選出勝出策略。
部分幾何／閉眼數值沿用既有候選；時間品質與 coverage 條件是本輪明確列出的設計選擇。

| 項目 | 條件 |
| --- | --- |
| 慢軌視窗 | 僅接受 `2000`／`3000` ms；PTS 滾動 |
| 起始校正 | 正坐、可用眼部與 Pose 持續 500 ms，鼻子高度取中位數；未完成則標 `calibrating` |
| 資料間斷 | 相鄰 PTS 超過 500 ms，清除觀察與事件證據，重新開始計時；保留已完成的基準 |
| 可靠幾何 | 鼻子與兩肩 visibility >= 0.5，座標在影像內，肩寬至少為影像高度的 0.05 |
| 低頭候選 | 可用 Pitch 達正式 `EyeStateDetector.readingPitchThreshold`，或鼻子相對基準下降 >= 0.06 個影像高度 |
| 可靠閉眼 | Face、兩眼 openness、Pitch／offset 皆可用，且 `raw_eye_closed` 與正式眼部閉眼判斷一致 |
| 閉眼後下降 | 正坐可靠閉眼 >= 300 ms；確認後 2000 ms 內發生鼻子下降 |
| 快速下降 | 500 ms 內兩個可靠 Pose 位置間，鼻子下降 >= 0.06 個影像高度 |
| 姿勢證據 | 持續低頭完整視窗，鼻子相對基準下降 >= 0.06，時間加權 Pose coverage >= 0.8 |
| `drowsy_like` | 閉眼後下降＋持續低頭姿勢，或明顯快速下降＋持續低頭姿勢；有大量可靠睜眼證據時不走單純動作路徑 |
| `reading_like` | 資料品質良好、眼部與 Pose coverage >= 0.8、睜眼時間比例 >= 0.8、無閉眼證據、Pitch 範圍 <= 3 度、鼻子範圍 <= 0.015 |
| `unknown_low_head` | 視窗成熟但證據不足／衝突；已有慢軌事件時缺資料也轉為 unknown |
| 保持與解除 | 已確認事件可保留本次低頭歷程的交叉證據；資料不足或證據衝突則降為 unknown；回正、可靠睜眼且鼻子回到基準 +0.05 以內持續 500 ms 後解除 |
| 仲裁順序 | `user_missing` > 正式 detector 確認且目前幾何可用的 `posture_down` > 正式 `distracted` > 慢軌 > 其他正式狀態 |

完整視窗以前，模糊低頭的最終輸出保持 `normal`；正式 `fast_status`／`fast_cause` 仍原樣留存。
正坐閉眼的正式 attention／fatigue 處理保留。

`evidence_eye`／`evidence_motion` 包含本次低頭事件已確認的證據，不一定只代表目前視窗內的變化。
另輸出 `motion_evidence_at_ms`、`eye_descent_at_ms`、`drowsy_confirmed`、
coverage、閉眼時長與幾何範圍，方便區分新證據與已確認事件。

## 工程驗證

| 檢查 | 結果 |
| --- | --- |
| 修改前交接指定的四份回歸測試 | 51 項通過 |
| 修改後全部 `test/vision` | 90 項通過，其中新增 26 項 |
| `flutter analyze --no-pub` | 無新增問題；仍有登入頁既有 13 項 `withOpacity` deprecated 提示，因此整體 exit code 為 1 |
| 原 replay 重構前後 | 合成 38 幀 fixture 的完整輸出逐位元相同 |
| 雙軌兩次執行 | 兩種時間窗各三種輸出逐位元相同，`fc.exe /b` 共六組無差異 |
| 快軌欄位 | 兩種時間窗的每列 frame／PTS／status／cause 與重構前 fixture 相同 |
| 原始資料 | 不覆寫；CLI 拒絕覆寫既有衍生檔 |
| 正式 App 接入 | 無 |

命令：

```powershell
flutter test --no-pub test\vision
flutter analyze --no-pub

dart run tool\vision_lab_dual_track.dart `
  test\fixtures\vision\dual_track_features.csv `
  test\fixtures\vision\dual_track_truth.csv `
  vision_lab_out\dual_track_task1\run_c --window-ms=2000
```

再以 `--window-ms=3000` 執行；另一輪改用 `run_d` 資料夾。
輸出檔名由輸入檔名決定，不包含執行時的時鐘時間。

```powershell
foreach ($window in @(2000, 3000)) {
  foreach ($kind in @('frames', 'events', 'metrics')) {
    $name = "dual_track_${kind}_${window}_dual_track_features.csv"
    fc.exe /b "vision_lab_out\dual_track_task1\run_c\$name" `
      "vision_lab_out\dual_track_task1\run_d\$name"
  }
}
```

`vision_lab_out/dual_track_task1/` 中的檔案皆是合成輸入的工程驗證產物，已受 Git ignore 保護。
不可用這些檔案宣稱閱讀／睡眠辨識成效。

## 限制與 Review 結論

1. 本機沒有朋友的 test6～test9 原始 CSV／GT，所以交接要求的「任選 test6 重跑」仍未完成。
2. 合成 fixture 只能證明時序、格式、仲裁與可重現性；無法證明雙軌優於單軌，也沒有選定 2 秒或 3 秒。
3. 初始鼻子基準依賴坐姿與相機位置；長期完全缺臉且從未取得可靠基準時，這輪不猜測睡眠。
4. 無交叉證據的靜止低頭睡眠可能維持 unknown，這是需要在真實資料報告的漏失風險。
5. 當前 GT 支援 `normal`／`reading`／`sleeping`；`transition` 等新標籤需在任務 3 Review 後明確訂定計分方式。
6. GT 只有 `normal`／`sleeping` 時，閱讀誤報欄位留空並標 `reading_labels_available=false`；不可把所有 normal 當成 reading。
7. unknown 仍計入總幀數，睡眠 GT 下的 unknown 算漏失；沒有只挑看得見臉的幀計分。
8. 最末事件的右邊界以最後 PTS 加相鄰 PTS 的中位間距估計，且不超過 GT 終點；分類視窗本身只使用實際 PTS。

下一步：先 Review 初始規則與本輪程式，取得 test6 CSV 補齊驗收；Review 通過後再進任務 2。
實機可以先觀察現有 App 的體驗或錄製素材。要比較雙軌與單軌，仍應保存同一份素材與人工 GT；
若決定改成實機同步記錄兩種策略，須另外確認測試入口與資料紀錄範圍，本輪尚未加入。

## 面試可使用的說法

> 我將原本的即時狀態判斷保留為快軌，另外實作依 PTS 運作的慢軌，對持續低頭整合閉眼與動作證據。
> 證據不足時保留 unknown，而不是強制判為睡眠。我目前完成離線工具、26 項新增測試與可重現性檢查；
> 下一階段才會用同一組影片與人工標記，評估誤報、漏失和延遲的取捨，目前還沒有宣稱辨識效果提升。
