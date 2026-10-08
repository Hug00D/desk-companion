# 雙軌時序判斷：開發交接與執行清單

最新進度（2026-10-08）請先讀
[`vision-lab-dual-track-progress.md`](vision-lab-dual-track-progress.md)。目前離線工具與自錄 V1／V2
補充候選已完成開發，但指定 test6 驗收、test6～test9 比較與獨立驗證仍待補，未接入正式 App。
下列保留原任務與驗收要求，不代表各任務已全部完成。

這份文件是給接手開發者直接執行的版本。研究理由與完整實驗設計請先讀：
[`vision-lab-dual-track-research-plan.md`](vision-lab-dual-track-research-plan.md)。

## 最重要的工作方式

依照下列任務順序進行，**每完成一個任務就停下來 review，不要一次做到正式 App**。

目前只授權做到：

1. 建立離線雙軌後處理器。
2. 用 test6～test9 比較 2 秒與 3 秒慢軌。
3. 輸出結果並更新測試紀錄。

在獨立影片驗證通過以前，不得把雙軌邏輯接入正式 App。

---

## 不可違反的護欄

- 開新 branch，不直接在 `main` 或既有實驗分支上開發。
- 不改 `CompanionStateEvaluator`、`PostureDownDetector`、`EyeStateDetector` 的正式行為。
- 不改正式 App 的預設提醒與畫面。
- MediaPipe 不重跑；先使用既有 test6～test9 的原始 CSV。
- 所有時間窗使用 `timestamp_ms`，不可用幀數換算秒數。
- 不覆寫原始 `frame_features_*.csv` 或 Ground Truth。
- 缺臉、缺眼睛或低 visibility 只能表示資料不足，不能直接當作閉眼／睡眠證據。
- `vision_lab_out/` 已被 Git 忽略，不得使用 `git add -f` 提交 CSV。
- test6～test9 已參與規則開發，只能叫開發／回歸資料，不能重新宣稱獨立驗證。
- 不新增 HTML 報告、圖表 UI、ML 模型、光學流、手部或呼吸辨識。

---

## 既有檔案地圖

| 用途 | 檔案 |
| --- | --- |
| 正式狀態 evaluator | `lib/vision/companion_state_evaluator.dart` |
| 正式回放工具 | `tool/vision_lab_replay_companion.dart` |
| 既有睡眠情境候選 | `tool/vision_lab_reclassify_sleep_context.dart` |
| 既有候選測試 | `test/vision/sleep_context_classifier_test.dart` |
| 事件與指標比較 | `lib/vision/vision_lab_comparison.dart`、`tool/vision_lab_compare.dart` |
| 正式 evaluator 回歸測試 | `test/vision/companion_state_cause_test.dart`、`test/vision/temporal_vision_logic_test.dart` |
| 實驗紀錄 | `docs/vision-lab-test-log.md` |
| 保守提醒策略 | `lib/focus/reminder_policy.dart`、`docs/reminder-policy-pilot.md` |

既有 `stable-arm`、`legacy-arm`、`shoulder-evidence` 結果必須保留；新工具不得悄悄取代它們的
預設模式。

---

## 任務 0：建立安全起點

### 操作

1. 從最新的 `codex/vision-lab-v2-pose-context` 建立新 branch，例如：

```powershell
git switch codex/vision-lab-v2-pose-context
git pull --ff-only
git switch -c feature/vision-lab-dual-track
```

2. 執行現有回歸測試：

```powershell
flutter test --no-pub `
  test\vision\sleep_context_classifier_test.dart `
  test\vision\companion_state_cause_test.dart `
  test\vision\temporal_vision_logic_test.dart `
  test\vision\vision_lab_comparison_test.dart
```

3. 記錄 baseline 測試數量與結果。若 baseline 已失敗，先停下回報，不要在雙軌修改中順便修。

### 驗收

- 新 branch 建立完成。
- 工作目錄沒有誤收既有圖片或 `vision_lab_out/` CSV。
- 上述測試在修改前通過。

完成後可直接進任務 1。

---

## 任務 1：建立離線雙軌後處理器

### 建議新增檔案

```text
lib/vision/dual_track_context_classifier.dart
tool/vision_lab_dual_track.dart
test/vision/dual_track_context_classifier_test.dart
```

分類器必須是純 Dart、可重設、可由 CLI 與未來正式 App 共用；但本任務只接 CLI，不接正式畫面。

### 輸入

讀取新版 46 欄 `frame_features_*.csv`。至少需要：

- `frame_idx`、`timestamp_ms`
- `face_detected`、`pose_detected`
- `eye_open_l`、`eye_open_r`
- `pitch`、`head_offset`
- `head_offset_calibrating`
- `image_width`、`image_height`
- 鼻子、左右肩膀的 X／Y／visibility
- `raw_eye_closed`

缺必要欄位時明確失敗並列出欄名，不得自動填 0。

### 快軌要求

- 快軌結果必須使用既有正式 `CompanionStateEvaluator` 回放，不得複製一份新的正式門檻。
- 先保留正式 status 與 cause，再由雙軌仲裁器決定最終輸出。
- `userMissing`、強 `postureDown`、明顯 `distracted` 可優先於慢軌。
- 新增慢軌前後，快軌欄位必須逐列相同。

若 `vision_lab_replay_companion.dart` 的 CSV 解析不方便重用，可把解析／回放共用部分抽成
`lib/vision/` 下的 helper，並以 regression test 證明既有 replay 輸出不變；不要複製整份解析器。

### 慢軌要求

- 支援 `--window-ms=2000` 與 `--window-ms=3000`。
- 視窗依真實 PTS 滾動，不假設固定 FPS。
- 只有持續低頭、又沒有快軌強事件時才進慢軌。
- 輸出三種慢軌結果：
  - `reading_like`
  - `drowsy_like`
  - `unknown_low_head`
- 單獨低頭、單獨缺臉、單獨低 EAR 都不足以輸出 `drowsy_like`。
- `drowsy_like` 至少需要兩類不同證據，例如：
  - 可靠閉眼持續＋後續頭部下降；
  - 明顯下墜／回彈＋持續低頭；
  - 正式強姿勢證據＋持續未恢復。
- 證據不足或互相衝突時輸出 `unknown_low_head`，不得硬判 `reading_like`。
- 慢軌解除需依時間戳確認回正穩定，不可用固定幀數。

本任務先完成資料結構與時序骨架。不要為了讓 test6～test9 分數變漂亮而新增影片專屬門檻。

### 必要輸出 CSV

不得覆寫原始欄位，另產生：

```text
dual_track_frames_<window>_<runId>.csv
dual_track_events_<window>_<runId>.csv
dual_track_metrics_<window>_<runId>.csv
```

逐幀檔至少包含：

```csv
frame_idx,timestamp_ms,fast_status,fast_cause,low_head_candidate,slow_state,slow_window_ms,evidence_eye,evidence_motion,evidence_posture,data_quality,final_state
```

布林證據欄位只能代表條件是否成立；需要診斷的原始數值另外留欄，不可只留下總分。

### CLI 介面

目標介面：

```powershell
dart run tool\vision_lab_dual_track.dart `
  <frame_features.csv> `
  <ground_truth_sleeping.csv> `
  <output_directory> `
  --window-ms=2000
```

同一輸入可再以 `--window-ms=3000` 執行。參數錯誤回傳非 0 exit code 並印出 usage。

### 必要自動測試

至少覆蓋：

1. 1999 ms 不完成 2 秒視窗，達 2000 ms 才成立。
2. 非等距 timestamp 仍依毫秒正確計算。
3. 短暫低頭不觸發慢軌事件。
4. 單獨缺臉不判睡眠。
5. 單獨閉眼不判低頭睡眠。
6. 閉眼證據＋後續下降可形成 `drowsy_like`。
7. 證據不足輸出 `unknown_low_head`。
8. 回正穩定後解除，不會永久 latch。
9. 快軌 `userMissing`／強趴下／分心可依優先序覆蓋慢軌。
10. `reset()` 清除所有跨幀狀態。
11. 相同輸入跑兩次逐列相同。
12. 快軌輸出與修改前正式 replay fixture 相同。

### 任務 1 完成標準

- 新增工具、分類器與測試。
- `flutter analyze` 無新增問題。
- 所有 Vision 測試通過。
- 任選一份 test6 CSV 跑兩次，`fc.exe /b` 無差異。
- 尚未修改正式 App。

**做到這裡停下來 review。不要先跑完所有影片、不要接正式 App。**

---

## 任務 2：test6～test9 的 2 秒／3 秒比較

任務 1 review 通過後才執行。

### 固定輸入

| 影片 | 原始特徵 CSV | Ground Truth |
| --- | --- | --- |
| test6 | `frame_features_test6_1788355603679529.csv` | `ground_truth_sleeping_test6_1788355603679529.csv` |
| test7 | `frame_features_test7_1788425425933008.csv` | `ground_truth_sleeping_test7_1788425425933008.csv` |
| test8 | `frame_features_test8_1788445572747073.csv` | `ground_truth_sleeping_test8_1788445572747073.csv` |
| test9 | `frame_features_test9_1788511300828684.csv` | `ground_truth_sleeping_test9_1788511300828684.csv` |

以上檔案都位於 `vision_lab_out/`。

### 比較組別

- 現行正式 replay baseline
- 雙軌 2 秒
- 雙軌 3 秒

不得加入 2.2、2.5、2.8 秒等額外掃描。先回答「2 秒或 3 秒哪個較合理」，避免建立新的
參數搜尋工程。

### 必須報告

- 各片與合計的 Precision／Recall／F1
- 閱讀誤報幀數與事件數
- 睡眠事件命中／漏失
- 狀態切換數
- onset delay
- `unknown_low_head` 幀數、比例與最長連續時間
- 快軌各狀態是否逐列不變
- 哪些事件因 2 秒與 3 秒而改變

把結果新增到 `docs/vision-lab-test-log.md`，不可覆寫舊實驗。

### 選擇規則

- 先排除會造成快軌回歸的版本。
- 再比較閱讀誤報與睡眠事件漏失。
- 如果 2 秒與 3 秒效果接近，選 2 秒以降低延遲。
- 如果兩者都不通過，保留失敗結果並停止，不再增加更多時間窗。

### 任務 2 完成標準

- 8 組輸出（4 支影片 × 2 個視窗）可重現。
- 測試紀錄含資料角色、參數、指標、失敗案例與限制。
- 明確選出 2 秒、3 秒，或「兩者皆不通過」。
- 規則與選擇結果 commit 後凍結。

**做到這裡停下來 review。不要自行錄 test10，也不要修改正式 App。**

---

## 任務 3：獨立驗證（由專題負責人提供影片與 GT）

只有任務 2 選出凍結策略後才開始。影片內容依研究計畫的 test10／test11 協議拍攝。

接手者的工作：

1. 使用 Vision Lab 逐幀抽取兩支新影片。
2. 驗證同片跑兩次 `frame_features.csv` 逐位元相同。
3. 等專題負責人提供 Ground Truth；不得自己看模型結果後修改 GT。
4. 只跑一次凍結策略。
5. 無論通過或失敗都寫入測試紀錄。
6. 不使用 test10／test11 回頭調整規則後再稱為獨立驗證。

完成後停下 review，由專題負責人決定是否進正式 App。

---

## 任務 4：正式 App（目前不要做）

只有獨立驗證通過且取得明確同意後才能做：

- 以 feature flag 接入，預設關閉。
- 共用任務 1 的分類器，不在畫面層複製規則。
- 保留原本 evaluator 結果，雙軌只負責介入／提醒仲裁。
- 補齊提醒冷卻、離席不提醒、不得重複轟炸等測試。
- 完成 45–60 分鐘自然使用測試後，再考慮是否成為預設。

---

## 每次 review 回報格式

```text
完成任務：
Branch / commit：
修改檔案：
執行測試：
測試結果：
產生的輸出：
與 baseline 的差異：
已知問題／失敗案例：
是否修改正式 App：否
下一步建議：
```

若遇到規格不確定，先停下並列出問題，不要自行擴張成新的辨識框架。
