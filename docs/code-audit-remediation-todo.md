# Desk Companion Code Audit 修正代辦與驗證紀錄

最後更新：2026-08-12

## 文件用途

本文件依據 2026-08-12 的 Flutter、Android/MediaPipe、番茄鐘、提醒、同步、Spring Boot 與統計架構 audit 建立，是後續修正工作的主要追蹤清單。

所有項目必須依本文件順序處理。每修正一個問題，必須在對應項目的「修改紀錄」補上實際修改方式、檔案與日期；取得模擬器、實機、Profiler、錄影回放或後端統計數據後，再補入「數據佐證」。不得只勾選完成而沒有留下驗證依據。

語音底層、STT、LLM、TTS 或播放器問題仍記錄於 [voice-system-maintenance-log.md](voice-system-maintenance-log.md)。若本文件的提醒政策修改同時影響語音播放流程，兩份文件都要更新，並互相註明問題編號。

## 狀態定義

- `未處理`：問題已確認，尚未開始修改。
- `進行中`：正在修改或補測試。
- `待實測`：程式與自動測試完成，尚未通過實際 App 流程驗證。
- `觀察中`：已完成初步驗證，仍需累積更多場景或數據。
- `已完成`：程式、自動測試與必要的實機／整合驗證均通過。
- `暫緩`：期末 Demo 前不建議修改，並已寫明原因。
- `已取消`：經實測證明不需處理，必須留下取消理由與證據。

## 更新規則

每次處理一個項目時，至少完成以下紀錄：

1. 將狀態改為 `進行中`。
2. 在修改前記錄可重現的症狀、輸入序列或目前數值。
3. 記錄修改日期、修改檔案、實作方式與是否涉及資料格式變更。
4. 記錄執行過的靜態分析、單元測試、整合測試與實機情境。
5. 有數據時記錄修改前後結果；沒有數據不得填寫推測值，改標示「尚無數據」。
6. 只有符合該項「完成條件」後，才可標記為 `已完成`。
7. 若發生回歸，直接在原項目追加紀錄，不另開內容重複的新項目。

## 建議執行順序總覽

- [ ] AUDIT-001：統一 status／cause 狀態模型、語意與門檻設定
- [ ] AUDIT-002：建立唯一 episode、duration、count 與統計來源
- [ ] AUDIT-003：集中番茄鐘狀態轉移、暫停原因與 round 同步
- [ ] AUDIT-004：抽出 ReminderManager 並接上提醒政策設定
- [ ] AUDIT-005：定義 Native 到 Flutter 的 FeatureFrame freshness contract
- [ ] AUDIT-006：修正 session 邊界並加入可持久化 outbox
- [ ] AUDIT-007：建立錄影回放與時序驗證，校正 baseline／latch
- [ ] AUDIT-008：拆分高頻 UI、降低 rebuild，清理重複與舊版程式

---

## AUDIT-001：統一 status／cause 狀態模型、語意與門檻設定

- 優先級：`High`
- 狀態：`進行中`
- 前置項目：無
- 目標：保留精簡且穩定的 UI 狀態，同時讓 detector、提醒、番茄鐘、事件與後端統計保有完整原因。

### 已確認問題

- `PoseState.postureDown` 與 `PoseState.drowsy` 映射成 `CompanionStatus.sleeping` 是刻意簡化 UI 的設計；真正問題是下游沒有穩定保留兩者的 cause。
- `StudySessionController` 將所有 `sleeping` 事件記為 drowsy。
- `posture_down_*.wav` 已存在，但現行提醒映射只會選擇 drowsy 音檔。
- `attention` UI 描述偏向「頻繁眨眼」，但目前訊號也可能來自短暫閉眼或短暫偵測不穩，文案過度指定單一原因。
- 狀態優先序雖有固定順序，但 `sleeping` 目前沒有可靠的 cause 隨流程傳遞，導致真正原因遺失。
- EAR、頭部角度、frame count、reading protection、提醒門檻與 cooldown 分散於多個檔案。

### 主要位置

- `lib/vision/companion_state_evaluator.dart`
- `lib/vision/vision_event.dart`
- `lib/vision/eye_state_detector.dart`
- `lib/vision/head_offset_detector.dart`
- `lib/vision/pose_state_detector.dart`
- `lib/vision/posture_down_detector.dart`
- `lib/focus/study_session_controller.dart`
- `lib/screens/face_detection_screen.dart`

### 建議修改

- 建立唯一狀態模型，分成 `CompanionStatus` 與 `CompanionCause`：status 用於 UI 顯示與主要狀態分類；cause 用於事件紀錄、語音提醒、`pauseReason` 與統計分析。

```dart
enum CompanionStatus {
  normal,
  attention,
  distracted,
  fatigue,
  sleeping,
  userMissing,
}

enum CompanionCause {
  none,
  frequentBlink,
  eyeClosed,
  headTurned,
  drowsy,
  postureDown,
  faceMissing,
  userAway,
}
```

- `drowsy` 與 `postureDown` 維持同一個 UI status：`sleeping`，但事件、提醒、pauseReason 與儲存必須依 cause 區分。
- 集中所有 native、detector、UI、API 的 `evidence → cause → status` mapping，禁止各檔案自行用字串重新判斷。
- `attention` enum 暫時保留；UI 文案改用「注意力波動」或「短暫注意力下降」，只有 cause 已確認時才顯示眨眼或閉眼等具體原因。
- 建立小型 `VisionPolicyConfig` 與 `ReminderPolicyConfig`，先集中常數，不導入遠端設定或新框架。
- 明確記錄並測試唯一 primary status 優先序；保留 evidence/cause，避免遺失同幀其他訊號。

### 狀態模型設計決策

- 前端主要狀態維持少量且可理解，不要求使用者分辨 drowsy 與 postureDown。
- `sleeping` 僅作 UI 群組，內部永遠保留明確 cause。
- 相同 status 的不同 cause 可以選擇不同提醒內容、pauseReason 和統計欄位。
- cause 是判斷依據，不代表同一時間必須顯示多個互相競爭的 UI 狀態。

### 完成條件

- [x] drowsy 與 postureDown 可作為 cause 從 detector 一路傳到事件、提醒與 session 統計；UI 可統一顯示為 `sleeping`。
- [x] `sleeping` 僅作 UI 群組，並保留明確 cause。
- [x] `evidence → cause → status` mapping 只有一個來源。
- [x] `attention` UI 使用中性文案；只有 cause 已確認時才顯示具體原因。
- [ ] 關鍵門檻集中並有單位註解，例如 frame、ms、degree、ratio。
- [ ] 既有 vision/focus tests 更新並通過。

### 修改紀錄

#### 2026-08-12｜導入 status／cause 兩層狀態模型

- 狀態變更：
  - 修改前：`未處理`
  - 修改後：`進行中`

- 修改背景：
  - 現有 `sleeping` 是刻意簡化 UI 的狀態，但 drowsy 與 postureDown 原因沒有穩定傳到提醒、pauseReason 與 session 統計。

- 修改檔案：
  - `lib/vision/companion_state_evaluator.dart`
  - `lib/vision/vision_event.dart`
  - `lib/companion/companion_controller.dart`
  - `lib/companion/companion_response_builder.dart`
  - `lib/focus/focus_session_monitor.dart`
  - `lib/focus/focus_session_report.dart`
  - `lib/focus/study_session_controller.dart`
  - `lib/focus/pomodoro_controller.dart`
  - `lib/screens/face_detection_screen.dart`
  - `lib/screens/tasks_screen.dart`
  - `test/focus/focus_session_monitor_test.dart`
  - `test/focus/focus_session_report_test.dart`
  - `test/focus/study_session_cause_test.dart`
  - `test/vision/companion_state_cause_test.dart`
  - `test/vision/temporal_vision_logic_test.dart`

- 修改方法：
  - 保留現有 `CompanionStatus`，新增 `CompanionCause` 與兩層狀態值；本次不調整 detector 門檻或姿勢演算法。
  - `CompanionAnalysis` 改為持有 `CompanionState`，並由 evaluator 的單一 mapping 將 evidence 解析成 status 與 cause。
  - `VisionEvent` 新增 cause，event type 與上傳 signals 依 cause 區分 `vision.drowsy_detected` 和 `vision.posture_down`。
  - `FocusIntervention` 與 session report 保留 cause count；`StudySessionController.recordFocusEvent` 依 cause 分別增加 drowsy 或 postureDown count。
  - `PomodoroPauseReason.sleeping` 拆為 `drowsy` 與 `postureDown`，UI 仍顯示同一個 `sleeping` 主狀態。
  - 本地提醒 request 同時攜帶 status/cause；drowsy 使用既有 drowsy 音檔，postureDown 使用既有 posture_down 音檔。
  - attention 相關狀態標籤與正式畫面文案改為「注意力波動」或「短暫注意力下降」。

- 修改後行為：
  - drowsy 與 postureDown 對前端角色狀態都仍是 `sleeping`，不增加 UI 判斷複雜度。
  - 兩種 sleeping cause 會產生不同 event type、提醒音檔、pauseReason 與 session count。
  - postureDown 不再經由 Focus intervention 路徑被固定計入 drowsyEventCount。
  - attention 畫面不再把所有注意力波動寫死成頻繁眨眼。

- 測試方式：
  - 對 14 個本次修改檔案執行 `flutter analyze`：0 issue。
  - 對 15 個實作與測試檔案執行 `dart analyze`：0 issue。
  - 執行 Focus monitor、Focus report 與 StudySession cause 測試，共 12 項全部通過。
  - 新增 drowsy/postureDown status-cause 與 VisionEvent mapping 測試；但 vision test runner 在載入前持續無輸出卡住，已有限等待後中止，尚未取得執行結果。

- 數據佐證：
  - 修改前：`recordFocusEvent(CompanionStatus.sleeping)` 無法知道原因，固定增加 `drowsyEventCount`；postureDown 提醒只會選 drowsy 音檔。
  - 修改後：自動測試分別輸入一筆 drowsy cause 與一筆 postureDown cause，結果為 `drowsyEventCount = 1`、`postureDownEventCount = 1`；Focus 相關 12 項測試全部通過。
  - 結論：Focus/session 路徑已證明 cause 不再被吃掉；Vision evaluator 與實際提醒音檔仍需補 runner 與實機佐證。

- 殘留風險：
  - `frequentBlink` 已保留在 cause enum，但目前 detector 尚未產生此 cause，不得宣稱已有頻繁眨眼辨識。
  - 相同 `sleeping` episode 中若 cause 由 drowsy 切換為 postureDown，Focus monitor 目前保留最新 cause；episode 拆分規則留待 AUDIT-002 統一。
  - 完整 temporal vision 測試與新增 vision cause 測試受本機 Flutter test runner 卡住影響，需排除工具問題後補跑。
  - 尚未在實體裝置確認 drowsy/postureDown 音檔內容、播放選擇及 Tasks pause caption。
  - 門檻常數集中尚未處理；本次刻意不移動或調整 detector threshold，避免在無 replay 數據時改變判斷結果。

#### 2026-08-12｜修正 attention 提醒的過度推論文案

- 狀態變更：
  - 修改前：`進行中`
  - 修改後：`進行中`

- 修改背景：
  - 實測 `attention / eyeClosed` 提醒播放「先把視線移開幾秒，眼睛會舒服一點」，但現有 detector 只能觀察短暫閉眼訊號，無法判斷使用者主觀上是否眼睛不舒服。

- 修改檔案：
  - `assets/audio/reminders/attention_3.wav`
  - `lib/screens/face_detection_screen.dart`
  - `backend/python_voice_service/app/main.py`
  - `docs/voice-system-maintenance-log.md`

- 修改方法：
  - 將文案改為「注意力好像有點波動，先眨眨眼、調整一下視線吧」。
  - 使用專案既有 Staff A GPT-SoVITS 產生新版固定 WAV。
  - 同步更新 Flutter clip 字幕、attention fallback 文案與 Python reminder catalog，避免固定音檔和動態生成再次出現舊句。

- 修改後行為：
  - `attention_3` 不再宣稱已判斷眼睛舒服程度，語意能涵蓋短暫閉眼、眨眼與辨識波動。
  - 播放音檔、畫面文字與動態 reminder catalog 使用相同句子。

- 測試方式：
  - 以 Python `wave` 模組檢查 RIFF/WAVE 結構、聲道、sample width、sample rate、frames 與時長。
  - 執行 Flutter 靜態分析與 Python 語法檢查。
  - 執行 Python voice service 8 項測試與 Focus monitor 8 項測試。
  - 搜尋舊文案，確認 runtime code 不再引用。

- 數據佐證：
  - 修改前：`attention_3.wav` 258,604 bytes；文案為「先把視線移開幾秒，眼睛會舒服一點」。
  - 修改後：新版 WAV 323,884 bytes、單聲道、16-bit、32 kHz、161,920 frames、5.06 秒。
  - 結論：音檔與程式文案已完成替換；Python voice service 8/8、Focus monitor 8/8 測試通過，尚待 App 實際播放確認語音內容與聽感。

- 殘留風險：
  - 尚未在 Android 模擬器或實機實際聽取新版固定音檔，因此 AUDIT-001 維持 `進行中`。

### 驗證與數據佐證

- 2026-08-12：Focus/session 自動測試 12/12 通過；本次修改檔案靜態分析 0 issue。
- 2026-08-12：依實測 attention Log，將會過度推論「眼睛舒服程度」的 `attention_3` 文案改為「注意力好像有點波動，先眨眨眼、調整一下視線吧」；以 Staff A GPT-SoVITS 生成 5.06 秒新版 WAV，並同步 Flutter 字幕與 Python catalog。尚待 App 實際播放確認。
- 待補：各狀態 replay 的 primary status、cause、event type、提醒音檔與後端 signals 對照。
- 待補：實體 Android 裝置上的 drowsy／postureDown 提醒選檔與 pauseReason 顯示。
- 待補：修復或繞過 vision test runner 無輸出卡住問題後，執行完整 temporal vision 測試。

---

## AUDIT-002：建立唯一 episode、duration、count 與統計來源

- 優先級：`High`
- 狀態：`未處理`
- 前置項目：AUDIT-001
- 目標：同一個異常 episode 只計數一次，完成報告、session snapshot 與後端統計得到一致結果。

### 已確認問題

- `VisionEventTracker`、`FocusSessionMonitor`、`StudySessionController` 各自累積穩定幀、時間或次數。
- 同一 episode 可能在 tracker persist 時記一次，又在 monitor 的 `eventRecorded` 門檻到達時再記一次。
- `reminderShownCount` 由部分異常 count 推算，不代表實際播放成功次數，也忽略部分狀態。
- 後端今日統計同時加 session reminderCount 與異常 behavior event 數量。
- Weekly trend 同時加 session aggregate duration 和 behavior event duration，可能重複計算。
- `focusSeconds == 0` 時以 monitored 減 abnormal 推算 focus，可能把未觀測 wall-clock 算成專注。
- `VisionEventTracker.shouldNotify` 形成另一套未被 UI 採用的提醒政策。

### 主要位置

- `lib/vision/vision_event_tracker.dart`
- `lib/focus/focus_session_monitor.dart`
- `lib/focus/study_session_controller.dart`
- `lib/focus/focus_sync_controller.dart`
- `lib/screens/face_detection_screen.dart`
- `backend/desk_companion_backend/src/main/java/com/deskcompanion/service/impl/StatisticsServiceImpl.java`

### 建議修改

- 定義唯一 stabilized episode stream，例如 `episodeStarted`、`episodeUpdated`、`episodeEnded`。
- 明確事件化 `reminderPlayed`、`pauseTriggered`，不要由 detection event 推算提醒或暫停次數。
- Session aggregate 作為統計主要來源；behavior events 只作明細或在 aggregate 缺失時 fallback。
- 移除或停止使用平行的通知與計數入口。
- 禁止用未確認有監控覆蓋的 wall-clock 推算 focusSeconds。

### 完成條件

- [ ] 一次持續分心只增加一次 distracted episode count。
- [ ] 實際未播放語音時 reminder count 不增加。
- [ ] Flutter 完成報告、上傳 snapshot 與後端今日／週統計數值一致。
- [ ] 行為事件與 session aggregate 不再重複加入同一秒數。
- [ ] 加入至少一個防止 double count 的整合測試。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：固定 60 秒 replay 中各 episode count、各狀態秒數、reminderPlayed 次數，以及 Flutter／API／資料庫三方結果。

---

## AUDIT-003：集中番茄鐘狀態轉移、暫停原因與 round 同步

- 優先級：`High`
- 狀態：`未處理`
- 前置項目：AUDIT-001、AUDIT-002
- 目標：按鈕、語音、導航與偵測自動暫停都走同一條狀態轉移與記錄流程。

### 已確認問題

- `_roundPausedAt` 主要在語音命令路徑更新。
- Tasks UI、導航暫停及 detector auto-pause 直接操作 `PomodoroController`，沒有一致更新 pause clock。
- round status 雖會由 listener 同步，但 pausedSeconds 與 actualSeconds 的語意可能因操作入口不同而不一致。
- `pauseReason` 已存在，但並非所有 pause 入口都一致記錄。
- 完成後只有報告流程，`FocusRoundType.breakTime` 尚未形成完整休息倒數閉環。

### 主要位置

- `lib/focus/pomodoro_controller.dart`
- `lib/focus/focus_sync_controller.dart`
- `lib/focus/focus_session_monitor.dart`
- `lib/screens/tasks_screen.dart`
- `lib/screens/face_detection_screen.dart`

### 建議修改

- 建立單一 Pomodoro transition observer，以 `oldState`、`newState`、`pauseReason` 為輸入。
- 由 observer 統一更新 pause clock、round status、session counters 和 backend event。
- UI、語音與 detector 只發出 start/pause/resume/stop command，不自行記錄副作用。
- 定義 `actualSeconds` 是否排除 paused time，並在 Flutter DTO、Java DTO 和統計計算中保持一致。
- 休息 round 只在期末規格明確要求時，以最小狀態流程補上。

### 完成條件

- [ ] 按鈕、語音、導航與自動暫停四種入口產生相同的 pause 記錄。
- [ ] 每個 pause 都有 pauseReason。
- [ ] pausedSeconds 與實際碼表誤差在允許範圍內。
- [ ] round、session snapshot 與後端資料一致。
- [ ] 若休息 round 暫不實作，文件與 UI 不宣稱已有完整休息倒數。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：四種 pause 入口各執行一次，列出預期／實際 pauseReason、pausedSeconds、actualSeconds 與資料庫 round status。

---

## AUDIT-004：抽出 ReminderManager 並接上提醒政策設定

- 優先級：`High`
- 狀態：`未處理`
- 前置項目：AUDIT-001、AUDIT-002
- 目標：提醒判斷、排程、播放與實際播放紀錄由單一元件管理，避免太吵與重複觸發。

### 已確認問題

- 現況不是一偵測就播；已有持續時間門檻、per-state cooldown、播放中 guard 與 priority pending。
- 現有「分心提醒」是累積約 3 秒，不是產品描述的「3 秒視窗內至少 2 次」。
- detector 的 frame window 與 monitor 的 duration threshold 疊加後，實際延遲會受 native/fallback 取樣頻率影響。
- cooldown 僅按狀態區分；不同狀態快速切換時可能連續播放多段語音。
- quiet mode、mute mode、sensitivity model/API 已存在，但未接入 runtime policy。
- Reminder policy、AudioPlayer 與大型畫面 State 仍耦合。

### 主要位置

- `lib/focus/focus_session_monitor.dart`
- `lib/preferences/companion_preferences.dart`
- `lib/api/preferences_api.dart`
- `lib/screens/face_detection_screen.dart`
- `assets/audio/reminders/`

### 建議修改

- 建立輕量 `ReminderManager`，負責滑動視窗／持續時間、per-state cooldown、全域最短播報間隔、priority queue、quiet/mute/sensitivity 與播放狀態。
- 先由產品選定「2 次／3 秒」或「持續 3 秒」其中一種，不同時保留兩套互相疊加的規則。
- 只在 AudioPlayer 確認開始播放後送出 `reminderPlayed`。
- 互動語音、提醒語音與番茄鐘暫停保持事件層解耦；提醒可提出 pause 建議，但不直接控制 session。
- 此項若改到播放器或互動語音協調，需同步更新 `docs/voice-system-maintenance-log.md`。

### 完成條件

- [ ] 相同狀態在 cooldown 內不重播。
- [ ] 不同狀態切換仍遵守全域最短播報間隔。
- [ ] quiet/mute 實際阻止播放，sensitivity 實際改變門檻。
- [ ] `reminderPlayed` 數量等於實際開始播放次數。
- [ ] 提醒本身不直接修改 Pomodoro，pause policy 由 session 層決定。
- [ ] 使用假時鐘完成 reminder policy 單元測試。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：10 分鐘 replay 的狀態事件數、語音播放數、被 cooldown 抑制數、不同狀態最短播報間隔及 quiet/mute 實測結果。

---

## AUDIT-005：定義 Native 到 Flutter 的 FeatureFrame freshness contract

- 優先級：`Medium`
- 狀態：`未處理`
- 前置項目：AUDIT-001
- 目標：Flutter 能明確知道 face/pose 結果是哪一幀、是否新鮮及是否可用，避免舊資料重複累計。

### 已確認問題

- 原生端合併 `lastFaceResult` 與 `lastPoseResult`，兩種 detector 更新頻率不同。
- 目前只有 `poseSequence`，沒有 `faceSequence`、各自 timestamp、age 或 fresh flag。
- Flutter 對 pose 有部分 freshness 防護，但 eye/head 沒有等價的 face freshness gate。
- detector 失敗時可能混合新失敗結果與另一類舊 cache。
- Flutter 讀取 `faceConfidence`／`poseConfidence`，但 native 沒有提供，後端 confidenceScore 因此通常為 null。
- `detectedObject` 在部分事件轉換路徑中遺失。

### 主要位置

- `android/app/src/main/kotlin/com/example/desk_companion/MediaPipeVisionManager.kt`
- `android/app/src/main/kotlin/com/example/desk_companion/MainActivity.kt`
- `lib/companion/companion_controller.dart`
- `lib/vision/vision_event.dart`
- `lib/focus/focus_sync_controller.dart`

### 建議修改

- 定義 `VisionFeatureFrame` contract，至少包含 `frameId`、`captureTimestampMs`、`faceSequence`、`poseSequence`、`faceTimestampMs`、`poseTimestampMs`、`faceFresh`、`poseFresh`。
- 為 face/pose 設定明確 max age；過期資料只能作畫面參考，不能增加 temporal counter。
- 確認 MediaPipe API 能提供的 confidence 語意；無法取得時不要捏造數值，欄位保持 null 並記錄原因。
- 補齊 detected object/cause 的事件傳遞。
- 加入 Kotlin payload 與 Dart parser 的 contract test。

### 完成條件

- [ ] pose-only 更新不會增加閉眼或 head offset 計數。
- [ ] face-only 更新不會讓舊 pose 再次確認 postureDown。
- [ ] 過期與失敗結果有明確 unavailable 狀態。
- [ ] Flutter parser 與 native payload contract test 通過。
- [ ] 後端收到的 timestamp、state、reason、duration 與可取得的 confidence 格式一致。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：face/pose cadence、payload age、丟幀比例、stale frame 被拒絕次數與修改前後誤觸發案例。

---

## AUDIT-006：修正 session 邊界並加入可持久化 outbox

- 優先級：`High`
- 狀態：`未處理`
- 前置項目：AUDIT-002、AUDIT-003
- 目標：只有有效番茄鐘期間進入專注統計，且離線、關頁或程序結束時不遺失重要事件。

### 已確認問題

- 進入偵測畫面就建立 study session，早於 Pomodoro 開始。
- normal focus 有 `isStudying` gate，但部分異常狀態在 Pomodoro 未開始時仍會累積。
- monitoredSeconds 以 session 建立後的 wall-clock 計算，可能包含背景、導航與未觀測時間。
- event buffer 僅存在記憶體。
- widget dispose 呼叫非同步 close 時無法保證最後 flush 完成；同步進行中也可能略過最後更新。
- 統計頁目前讀取真實後端 API，不是寫死資料，但沒有 durable local fallback。

### 主要位置

- `lib/focus/study_session_controller.dart`
- `lib/focus/focus_sync_controller.dart`
- `lib/focus/companion_event_buffer.dart`
- `lib/screens/face_detection_screen.dart`
- `lib/screens/statistics_screen.dart`

### 建議修改

- 明確區分 camera monitoring session 與 Pomodoro focus session。
- 所有 focus/abnormal/away duration 使用一致的 Pomodoro running gate；若要記錄非番茄鐘監控，使用不同 session type。
- App lifecycle、camera suspended 與 navigation gap 不計入 monitored focus，除非規格明確要求。
- 實作最小 durable outbox：先落本機，再依 `clientEventId` 上傳與去重。
- 統計頁明確顯示資料來源與最後同步狀態；不要把 demo/mock 與 real data 混合。

### 完成條件

- [ ] 未開始 Pomodoro 時不增加專注 session 的任何狀態秒數與 count。
- [ ] 背景或 camera suspended 時間不被算成有效監控。
- [ ] 斷網建立的事件在重啟 App 後仍存在並可補傳。
- [ ] 重送不會在後端產生重複 behavior event。
- [ ] 統計頁能區分已同步、待同步與無資料。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：離線事件數、重啟後保留數、成功補傳數、重複事件數，以及 5 分鐘 Pomodoro 的本機／後端秒數差異。

---

## AUDIT-007：建立錄影回放與時序驗證，校正 baseline／latch

- 優先級：`Medium`
- 狀態：`未處理`
- 前置項目：AUDIT-001、AUDIT-005
- 目標：用可重現數據驗證 baseline、狀態優先序、frame/time threshold 和恢復邏輯，而不是直接憑體感改參數。

### 需要實測確認的問題

- 穩定側看可能被 head baseline 接受。
- Posture baseline 可能在初始彎腰、肩膀不穩或垃圾幀建立。
- 從 postureDown 恢復時 reset baseline 的時機可能太早。
- postureDown latch 在離席後可能維持過久，延遲轉成 userMissing。
- frame-based threshold 在 native 約 600 ms 與 fallback 約 800 ms cadence 下代表不同實際時間。
- `_recentStrongPostureCandidateFrames` 等 temporal 資料是否會被 stale pose 延長。

### 主要位置

- `android/app/src/main/kotlin/com/example/desk_companion/MediaPipeVisionManager.kt`
- `lib/vision/companion_state_evaluator.dart`
- `lib/vision/posture_down_detector.dart`
- `lib/vision/head_offset_detector.dart`
- `test/vision/`

### 建議修改

- 建立至少五組固定 replay：正常、閱讀低頭、閉眼、趴下、離席。
- 額外加入側看校正、初始彎腰、遮鏡頭、趴下後離席和回座案例。
- 測量每組影片的輸入時間、state transition、首次提醒、pause 與 recovery 時刻。
- threshold 優先改用 duration/timestamp；只有得到數據後才調整姿勢分數與 latch 值。
- calibration 需高品質連續樣本；reset 優先由鏡頭重啟或使用者動作觸發。

### 完成條件

- [ ] replay 可重複產生相同狀態序列。
- [ ] 每個案例有預期結果與容許時間誤差。
- [ ] baseline 不會由已知錯誤起始姿勢建立。
- [ ] 趴下後離席能在規格時間內轉為 userMissing。
- [ ] 所有 threshold 修改均附修改前後數據。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據；此項不得在沒有 replay 或實機紀錄時宣稱完成。
- 建議表格欄位：案例、裝置、FPS/cadence、預期狀態、實際狀態、偵測延遲、提醒延遲、誤判次數、版本／commit。

---

## AUDIT-008：拆分高頻 UI、降低 rebuild，清理重複與舊版程式

- 優先級：`Medium / Low`
- 狀態：`未處理`
- 前置項目：AUDIT-001 至 AUDIT-006 穩定後
- 目標：在不更換框架的前提下降低大型畫面的維護風險與正式版不必要工作。

### 已確認問題

- `FaceDetectionScreen` 約五千行，混合 camera、vision、提醒、wake word、assistant、Pomodoro、sync、debug 與 UI。
- MediaPipe result 與 Pomodoro tick 都可能對整頁呼叫 `setState`。
- 每次 vision result 都建立並輸出長 debug 字串。
- 存在多個 `ignore: unused_element`、未使用 serializer、未引用 mock JSON 與未使用的 full pose model。
- mock/demo 與 real code 位於同一畫面，資料來源界線不明顯。
- Active Flyway migration 與 `backend/migrations` 舊 SQL 並存。
- `userReturned` 被標為 warning severity。
- `login_screen.dart` 尚有 `withOpacity` deprecated info。

### 主要位置

- `lib/screens/face_detection_screen.dart`
- `lib/widgets/live2d_character_background.dart`
- `lib/vision/vision_event.dart`
- `lib/focus/companion_event_buffer.dart`
- `lib/screens/statistics_screen.dart`
- `assets/mock/`
- `android/app/src/main/assets/`
- `backend/desk_companion_backend/src/main/resources/db/migration/`
- `backend/migrations/`

### 建議修改

- 只拆出高頻區域：vision state notifier、ReminderManager、Pomodoro status panel。
- 使用現有 `ValueNotifier`／`ListenableBuilder` 或局部 widget state，不導入新的全域狀態管理框架。
- release/profile build 關閉詳細 landmarks/debug string 更新。
- demo/mock 工具以 `kDebugMode` 或明確的 demo flag 隔離；確認無使用後才刪除。
- README 指定 Spring resources 中的 Flyway migration 為唯一 schema 來源，舊 SQL 標成 legacy。
- 修正 recovery severity、deprecated API 與確認後可安全移除的資產。

### 完成條件

- [ ] Vision 更新不再重建不相關的整個畫面區塊。
- [ ] release/profile 模式不輸出每幀詳細 landmark log。
- [ ] 所有刪除項目先經引用搜尋與 build/test 驗證。
- [ ] mock/demo/real data source 在程式與 UI 中可辨識。
- [ ] migration 唯一來源有文件說明。
- [ ] `flutter analyze` 無 error/warning；deprecated info 依排程處理。

### 修改紀錄

#### YYYY-MM-DD｜修改標題

- 狀態變更：
  - 修改前：
  - 修改後：

- 修改背景：
  -

- 修改檔案：
  -

- 修改方法：
  -

- 修改後行為：
  -

- 測試方式：
  -

- 數據佐證：
  - 修改前：
  - 修改後：
  - 結論：

- 殘留風險：
  -

### 驗證與數據佐證

- 尚無數據。
- 待記錄：Flutter DevTools rebuild count、frame build/raster time、記憶體、release log 量、APK 大小與修改前後比較。

---

## 暫緩項目：期末 Demo 前不要直接大改

### HOLD-001：全面更換狀態管理或架構框架

- 狀態：`暫緩`
- 原因：全面導入 Riverpod、Bloc、Clean Architecture 或大型 DI 的回歸風險高，無法直接改善目前最嚴重的狀態語意與重複計數。
- 重新評估時機：AUDIT-001 至 AUDIT-006 完成且期末 Demo 結束後。

### HOLD-002：重寫 MediaPipe／CameraX pipeline

- 狀態：`暫緩`
- 原因：現有 `RunningMode.VIDEO`、單一 executor、`KEEP_ONLY_LATEST`、Face/Pose throttle 與 resource close 方向正確。
- 重新評估條件：Android Profiler 證明 CPU、GC、thermal 或掉幀超出目標。

### HOLD-003：無數據調整 posture、EAR、yaw/pitch 與 latch 大量參數

- 狀態：`暫緩`
- 原因：門檻互相影響，缺少 replay 資料時容易修好單一案例卻破壞閱讀或離席情境。
- 重新評估條件：AUDIT-007 已建立可重現測試與基準數據。

### HOLD-004：大幅重做 Spring Boot schema 或同步架構

- 狀態：`暫緩`
- 原因：目前 schema 已可容納 session、round、behavior event、timestamp、duration、state/reason 與 confidence；近期風險在計算與資料來源，不在資料表全面不足。
- 重新評估時機：修正統計重複計算與本機 outbox 後。

### HOLD-005：立即刪除所有 demo/mock、語音或模型資產

- 狀態：`暫緩`
- 原因：部分內容可能仍用於期末展示或離線 fallback。先隔離並確認引用，再於 AUDIT-008 安全清理。

## 全案最低驗收

1. 執行 `flutter analyze`，記錄 warning/error 數量。
2. 執行 focus、vision、serialization 相關 Flutter tests；若 runner 卡住，需記錄卡住的測試與環境，不得只寫「未通過」。
3. 執行 Spring Boot tests，確認 session、event dedupe 與 statistics 計算。
4. 至少在一台實體 Android 裝置驗證正常、閱讀、分心、閉眼／嗜睡、趴下、離席與恢復。
5. 完成一次完整流程：開始任務 → 偵測 → 提醒 → 暫停／恢復 → 完成 → 同步 → 統計。
6. 對照 Flutter completion report、上傳 payload、資料庫與 Statistics API，確認 count 與 seconds 一致。
7. 記錄裝置、App 版本／commit、測試日期、影片或輸入序列、預期值與實際值。

## 數據紀錄範本

後續取得數據時，將下列區塊複製到對應 AUDIT 項目的「驗證與數據佐證」下方：

```text
- 日期：YYYY-MM-DD
- 版本／commit：
- 裝置／環境：
- 測試案例：
- 修改前：
- 修改後：
- 樣本數／測試時間：
- 預期結果：
- 實際結果：
- 結論：通過／未通過／需要更多資料
- 殘留風險：
```
