# Vision Lab Pilot v1 — 完成標準

> **做到這裡就停手。**
>
> 目的只有一個：在拿到第一個數字後收手，不要往完美 harness 蓋過去。

## 唯一任務

在 2–3 段影片上，產出「**單幀 vs 3-of-5**」的一次**可重現**比較，拿到**誤報**與**延遲**的數字。以下全打勾後，停止開發並把結果寫進研究計畫。

## Done =

### 1. 可重現的逐幀特徵抽取

- [ ] 影片由原生端**逐幀解碼**，每幀用**影片真實 PTS** 當 timestamp（非系統時間、非 UI 驅動）。
- [ ] 同一部影片跑兩次，`frame_features.csv` **逐列相同**（跑兩次 `diff` 為空，作為可重現驗收）。
- [ ] CSV 至少包含：

```text
frame_idx, timestamp_ms, face_detected, pose_detected,
ear_l, ear_r, yaw, pitch, head_offset,
raw_eye_closed, raw_head_turned, raw_posture_down,
raw_user_missing, raw_state
```

### 2. 單幀規則是「乾淨的」baseline

- [ ] `FrameClassifier` **只看當前列、零記憶**，無計數器、確認幀、鎖定或 cooldown。
- [ ] 拿一段已確認內容的影片檢查：單幀輸出**確實會抖**（眨眼的幾幀會跳成閉眼）。這代表 baseline 沒有時序穩定，對照才有意義。

### 3. 時序策略在後處理，不重跑 MediaPipe

- [ ] 一個 script 讀取 `frame_features.csv`，套用 **3-of-5 投票**，輸出 `predicted_events.csv`：

```text
state, start_ms, end_ms
```

- [ ] 切換成「單幀（不投票）」時，也從**同一個 CSV** 產出事件，證明只換策略、不重跑推論。

### 4. Ground Truth + 一次比較

- [ ] 準備 **2–3 段影片**，各自人工建立 `ground_truth.csv`，內容至少涵蓋：正常、眨眼、短暫轉頭、一次真的疲勞／趴下、一次離席。
- [ ] 一個 script 比對 predicted 與 ground truth，算出：
  - 誤報數
  - 漏失數
  - 狀態切換次數
  - 偵測延遲（已配對事件的 `predicted_onset - true_onset`）
- [ ] 單幀與 3-of-5 各產出一組數字。

### 5. 能講出一句話

- [ ] 能寫出：

> 在 N 段影片上，3-of-5 把眨眼誤觸發從 **X → Y**，狀態切換 **A → B**，代價是平均延遲增加約 **Z 秒**。

全數完成後停止開發，把這句與數字寫進研究計畫 **§五**，將「預計比較」改成「**初步觀察到**」；面試時也使用這項結果。

## v1 明確先不要做

- HTML 報告／圖表
- SHA-256／provenance
- 5-of-7／遲滯／cooldown 全掃描
- 資料夾階層
- 批次多影片
- 畫面內標註工具
- blendshape／filtered／visibility 全欄位（先留位）

## 一句話收斂

> **v1 = 一個可重現的 CSV + 兩組數字 + 一句話。做到就收手。**

## 執行提醒

真正的工作只有兩項：

1. 使用真實 PTS 逐幀解碼。
2. 拆出零記憶的單幀規則。

後續比較與統計應保持簡單。不要讓報告外觀或額外實驗功能把工作重心從這兩項移開；兩項驗收通過後，直接取得第一組比較數字。

## 實作檔案地圖

開始前先查看以下既有位置，不重新搜尋或另建重複路徑：

- PTS／現有測試影片抽幀：
  - `android/app/src/main/kotlin/com/example/desk_companion/MainActivity.kt:330`
  - `lib/screens/face_detection_screen.dart:566`
- 拆出零記憶單幀規則：
  - `lib/vision/companion_state_evaluator.dart:84`
- 特徵融合與座標：
  - `android/app/src/main/kotlin/com/example/desk_companion/MediaPipeVisionManager.kt:185`
  - `lib/vision/vision_result.dart:79`

## 分段執行與強制停點

實作必須依序進行；每一段完成後停止，交由使用者 review。未通過前不得開始下一段。

1. **任務 1：真實 PTS 逐幀解碼 → `frame_features.csv`**
   - 完成後停止。
   - 驗收：同一部影片跑兩次，兩份 CSV 的 `diff` 為空。
2. **任務 2：拆出零記憶 `FrameClassifier`**
   - 僅在任務 1 通過後開始。
   - 完成後停止。
   - 驗收：已確認影片的單幀輸出確實會抖，眨眼幀會短暫跳成閉眼。
3. **任務 3：單幀與 3-of-5 比較 script**
   - 僅在任務 2 通過後開始。
   - 從同一份 `frame_features.csv` 產出兩組事件與比較數字，不重跑 MediaPipe。

## 實作護欄

- 所有實作放在獨立 branch，不得直接修改 `main`。
- 不得改變正式 app 的既有行為。
- Vision Lab 必須使用獨立 entry point／獨立執行路徑。
- 正式 app 與 Vision Lab 共用同一套特徵計算，不複製另一套特徵公式。
- 拆分 `CompanionStateEvaluator` 時，原本 live app 的判斷結果不得改變。
- 只實作滿足本文件驗收條件的最小內容。
- 「v1 明確先不要做」所列項目不得實作。
