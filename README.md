# Desk Companion

Desk Companion 是一個以「桌面陪伴式專注學習」為主題的行動應用專題。系統透過手機鏡頭偵測使用者的臉部、眼睛、頭部角度與上半身姿態，判斷是否出現疲勞、分心、低頭趴睡或離席等狀態，並以互動角色、提醒語音、番茄鐘與統計頁面協助使用者維持讀書或工作的專注節奏。

本專案採用 Flutter 作為主要 App 介面，Android 原生層整合 MediaPipe 視覺模型，後端以 Spring Boot 提供帳號、登入與個人資料 API，資料庫使用 PostgreSQL 與 Flyway migration 管理 schema。另有一個 Python voice service，可在本機測試「提醒文字轉語音」流程。

## 專題目標

- 建立一個能陪伴使用者讀書或工作的桌面助理 App。
- 使用手機前鏡頭進行即時狀態辨識，而不是只依賴手動打卡或計時。
- 將視覺偵測結果轉換成可理解的狀態，例如正常、注意力下降、疲勞、分心、趴睡、離席。
- 透過 Rive 互動角色、文字提示、語音提醒與番茄鐘，給予使用者即時回饋。
- 保留帳號、個人資料、專注事件與統計資料的後端資料模型，讓專注歷程可被追蹤與擴充。

## 主要功能

### 1. 帳號與個人資料

- Email / password 註冊與登入。
- BCrypt 密碼雜湊驗證。
- 忘記密碼、重設密碼、帳號復原流程的後端 API。
- 個人資料讀取與更新。
- 前端以 `AuthSession` 保存目前登入使用者資訊。

### 2. 即時視覺偵測

- Flutter camera 串接 Android 原生 MediaPipe vision module。
- Face Landmarker 偵測臉部、眼睛開合與頭部姿態。
- Pose Landmarker 偵測肩膀、鼻子、眼睛、耳朵等上半身姿態點。
- 前端偵測器會分析：
  - 使用者是否在鏡頭前
  - 眼睛是否長時間閉合
  - 頭部是否偏移或低頭
  - 是否出現趴睡 / posture down 狀態
  - 是否可能離席

### 3. AI 互動陪伴

- 使用 Rive 動畫作為桌面陪伴角色背景。
- `CompanionStateEvaluator` 將 MediaPipe 原始結果整合成陪伴狀態。
- `CompanionController` 與 response builder 根據狀態產生提醒訊息。
- 當偵測到疲勞、分心、趴睡等狀況時，App 可顯示提醒並觸發語音服務。

### 4. 番茄鐘與專注事件

- 內建 Pomodoro controller 與 study session controller。
- 將專注、分心、疲勞、離席與提醒次數整理成 session snapshot。
- `CompanionEvent` 與 event buffer 定義前端事件上傳格式，方便後續串接後端統計。

### 5. 統計與設定頁面

- 提供統計頁、個人中心、個人資料頁等 Flutter screens。
- 統計資料模型包含今日專注秒數、狀態分布、每週趨勢與近期事件。
- 目前畫面中部分統計內容仍偏展示 / demo 資料，後端統計 controller 尚未完整落地。

### 6. 本機語音服務

- `backend/python_voice_service` 提供 `POST /tts` 測試端點。
- Windows 環境會優先嘗試 System.Speech TTS，失敗時產生 mock WAV。
- Flutter 端可透過 `VOICE_SERVICE_URL` 指定語音服務位置。

## 使用技術

### Frontend / Mobile

- Flutter
- Dart
- Material 3
- camera
- video_player
- video_thumbnail
- path_provider
- audioplayers
- rive
- http

### Android Native Vision

- Kotlin
- Android CameraX
- MediaPipe Tasks Vision `0.10.33`
- Face Landmarker
- Pose Landmarker
- Flutter MethodChannel

### Backend

- Java 17
- Spring Boot `3.5.13`
- Spring Web
- Spring Data JPA
- Spring Validation
- Spring Security Crypto
- Spring Boot Actuator
- Maven

### Database / Deployment

- PostgreSQL 17
- Flyway migration
- Docker
- Docker Compose

### Voice Service

- Python
- Local HTTP TTS mock service
- Windows System.Speech fallback

### Testing

- Flutter unit tests
- Spring Boot tests
- API contract tests in `backend/testApi/api-tests.http`

## 系統架構

```text
Flutter App
  |-- Login / Register / Profile screens
  |-- FaceDetectionScreen
  |-- Pomodoro and study session controllers
  |-- Companion state and event models
  |
  | MethodChannel
  v
Android Native Layer
  |-- MediaPipe Face Landmarker
  |-- MediaPipe Pose Landmarker
  |-- Head / eye / pose metrics
  |
  v
Flutter State Evaluator
  |-- normal
  |-- attention
  |-- fatigue
  |-- distracted
  |-- drowsy
  |-- postureDown
  |-- userMissing

Flutter App ---- HTTP ---- Spring Boot Backend ---- PostgreSQL
     |
     +---- HTTP ---- Python Voice Service
```

## 專案目錄

```text
lib/
  api/                 Flutter API client and backend API wrappers
  auth/                Login session state
  companion/           Companion response and state control
  events/              Behavior event models and upload buffer
  focus/               Pomodoro and study session logic
  preferences/         Companion preferences models
  screens/             Login, vision, profile and statistics screens
  statistics/          Statistics response models
  vision/              Vision result parsing and state evaluators
  voice/               Voice command and voice service client
  widgets/             Shared UI widgets

android/app/src/main/
  assets/              MediaPipe task files
  kotlin/...           Native MediaPipe vision manager and MainActivity

backend/
  desk_companion_backend/   Spring Boot backend
  python_voice_service/     Local TTS service for reminder testing
  docker-compose.yml        Backend and PostgreSQL services
```

## 後端資料表設計

Flyway migration 目前建立的主要資料表包含：

- `users`: 使用者帳號、email、password hash、Google auth id、帳號狀態。
- `verification_tokens`: 驗證、重設密碼與帳號復原 token。
- `profiles`: 使用者顯示名稱與頭像。
- `character_stats`: 陪伴角色好感度與互動狀態。
- `focus_sessions`: 專注 session、專注秒數、分心秒數、離席秒數與摘要 JSON。
- `behavior_events`: 視覺 / 番茄鐘 / 語音等事件紀錄。
- `chat_history`: 使用者與助理互動紀錄。
- `user_memories`: 使用者短期 / 長期記憶資料。

## 已實作後端 API

主要 base path 為 `/api/v1`。

### Auth

```text
POST /auth/login
POST /auth/forgot-password
POST /auth/reset-password
POST /auth/account-recovery
POST /auth/account-recovery/confirm
POST /auth/validate-reset-token
```

### Users

```text
POST   /users/register
DELETE /users/{userId}
```

### Profile

```text
GET /users/{userId}/profile
PUT /users/{userId}/profile
```

## 環境需求

- Flutter SDK
- Android Studio 或 Android SDK
- JDK 17
- Docker Desktop
- PostgreSQL client, optional
- Python 3, optional for voice service

## 執行方式

### 1. 安裝 Flutter dependencies

```powershell
flutter pub get
```

### 2. 啟動後端與資料庫

從專案根目錄執行：

```powershell
cd backend
docker compose up --build
```

服務啟動後：

- Spring Boot backend: `http://localhost:8080`
- PostgreSQL: `localhost:5432`
- Health check: `http://localhost:8080/actuator/health`

### 3. 啟動 Flutter App

預設 API 位置定義於 `lib/api/api_client.dart`：

```dart
String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://100.119.136.81:8080/api/v1',
)
```

如果要連本機後端：

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
```

如果使用實體 Android 手機，請把 `10.0.2.2` 換成電腦在同一個 Wi-Fi / LAN 下的 IP，例如：

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8080/api/v1
```

### 4. 啟動語音服務（AI 動態語音需要）

```powershell
python backend\python_voice_service\app\main.py --host 0.0.0.0 --port 8001
```

Spring Boot 會在 AI 產生文字後呼叫此服務，下載 WAV，並將文字與
Base64 音訊放在同一個 `/assistant/chat` 或 `/assistant/decide` 回應。
本機 Spring Boot 預設會呼叫：

```text
http://localhost:8001
```

Flutter 不需要直接連線到 Python 才能播放 AI 聊天語音；只需連到
Spring Boot：

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.23:8080/api/v1
```

`VOICE_SERVICE_URL` 仍保留給 Flutter 的語音服務 Debug/健康檢查工具，
不再用於 AI 聊天回覆主流程。

## 測試

### Flutter tests

```powershell
flutter test
```

目前測試涵蓋：

- vision state regression
- companion event serialization
- event buffer acknowledgement
- study session payload format
- voice event privacy contract
- statistics ratio calculation

### Backend tests

```powershell
cd backend\desk_companion_backend
.\mvnw test
```

### Manual API tests

可參考：

```text
backend/testApi/api-tests.http
```

## Vision Lab（離線視覺量測）

Vision Lab 是與正式 app 分離的量測工具，用途是在**已錄好的影片**上逐幀抽取視覺特徵，
產生可重現的 `frame_features.csv`，供後續比較不同時序判斷策略（單幀 vs N-of-M 投票）使用。

它有獨立的 entry point，不會影響正式 app 的行為；特徵計算與正式 app 共用同一套
`MediaPipeVisionManager`，不另外複製一份公式。

### 為什麼要離線跑

即時相機的每一次執行都不一樣，無法用來比較策略。改成讀固定影片、用**影片本身的
presentation timestamp（PTS）**當時間軸後，同一支影片跑兩次會得到逐列相同的 CSV，
策略比較才有意義。

### 啟動方式

測試影片放在 `assets/`，由 `lib/main_vision_lab.dart` 的 `_assetPath` 指定
（目前是 `assets/test.mp4`）。要換影片就改這個常數，並確認 `pubspec.yaml` 的 `assets:` 有登錄。

不需要相機，模擬器即可執行（MediaPipe 有 x86_64 native library，且走 CPU 推論）：

先在一個 PowerShell 視窗啟動輸出監看器，它會在每次分析完成後自動把新 CSV 拉到
專案根目錄的 `vision_lab_out/`：

```powershell
.\tool\watch_vision_lab_output.ps1
```

再從另一個 PowerShell 視窗啟動 Lab（裝置 ID 可換成實際模擬器或手機）：

```powershell
flutter run -d emulator-5554 -t lib/main_vision_lab.dart
```

畫面上的影片只是預覽，**不驅動推論**。按下「產生 frame_features.csv」後，由原生端
`OfflineVideoFrameDecoder` 以 MediaCodec 逐幀解碼並送進 MediaPipe。每按一次產生一個
新檔，不會覆蓋前一次的結果。監看器只會拉取已完成的
`frame_features_<runId>.csv`，不會把尚在寫入的 `.native` 暫存檔當成結果。

`<runId>` 的格式是 `<影片名>_<microseconds>`，例如 `assets/test.mp4` 會產生
`frame_features_test_1787902528095107.csv`。影片名取自 `_assetPath`，因此多支影片的
輸出放在同一個目錄也能一眼分辨；`ground_truth_<runId>.csv` 與比較結果都沿用同一個
`<runId>`，避免把某支影片的預測配到另一支的 Ground Truth。

進度可從 logcat 觀察（每 100 幀一筆）：

```powershell
adb logcat -s VisionLab
```

### 取出資料

平常直接使用上面的監看器即可。若只想同步一次，可執行：

```powershell
.\tool\watch_vision_lab_output.ps1 -Once
```

若同時連接多台裝置，可加上 `-DeviceId <裝置 ID>`。CSV 原始位置是 app 的外部專屬目錄；
需要手動處理時也可以執行：

```powershell
adb pull /storage/emulated/0/Android/data/com.example.desk_companion/files/ .\vision_lab_out
```

### 可重現性驗收

同一支影片跑兩次，兩份 CSV 必須逐列相同：

```powershell
fc.exe /b .\vision_lab_out\frame_features_<run1>.csv .\vision_lab_out\frame_features_<run2>.csv
```

輸出若只有「正在比較檔案」而沒有差異訊息，就代表逐位元相同。PowerShell 的 `fc` 是
`Format-Custom` 的別名，因此這裡要明確使用 `fc.exe`。

### 記錄哪些數據

每一幀一列，共 14 欄：

| 欄位 | 意義 | 備註 |
| --- | --- | --- |
| `frame_idx` | 已輸出幀的序號，從 0 開始 | 解碼器若略過某個 sample，序號仍連續，因此**不等於**容器內的 sample 序號 |
| `timestamp_ms` | 影片真實 PTS（毫秒） | 來自 `MediaCodec` 的 `presentationTimeUs`，非系統時間、非 UI 幀率 |
| `face_detected` | 該幀是否偵測到臉 | `true` / `false` |
| `pose_detected` | 該幀是否偵測到姿態 | `true` / `false` |
| `ear_l` / `ear_r` | 左／右眼 Eye Aspect Ratio | 眼睛垂直距離 ÷ 水平距離，值越小越接近閉眼；**純單幀計算** |
| `yaw` | 頭部左右轉角（度） | 由 MediaPipe facial transformation matrix 求得；**純單幀計算** |
| `pitch` | 頭部俯仰角（度） | 同上；**純單幀計算** |
| `head_offset` | 頭部偏移分數（0–100） | **含跨幀狀態**，見下方說明 |
| `raw_eye_closed` | 單幀規則：是否閉眼 | 僅使用當列 EAR、pitch 與 head offset |
| `raw_head_turned` | 單幀規則：是否轉頭 | 當列 `head_offset >= 55` |
| `raw_posture_down` | 單幀規則：是否趴下 | Pilot 固定規則：有 pose，且無 face 或 `abs(pitch) >= 35` |
| `raw_user_missing` | 單幀規則：是否離席 | 同一列 face 與 pose 都未偵測到 |
| `raw_state` | 單幀規則綜合狀態 | 優先序：離席 → 趴下 → 轉頭 → 閉眼 → 正常 |

偵測不到臉的幀，臉部相關欄位留空字串而不是填 0，以免把「沒有資料」誤當成「數值為 0」。

### 兩個使用時必須知道的性質

**1. `head_offset` 不是純單幀特徵。**
它需要先蒐集 5 個穩定樣本建立基準線，期間固定回傳 `0.0`；之後的值是
指數平滑後的指標與基準線中位數的差，再乘上比例並限制在 0–100。
因此開頭數幀的 `head_offset` 不能與後段直接比較，而且這個輸入特徵本身帶有原生端的
校正與平滑。Pilot 的 `FrameClassifier` 仍只讀取 CSV 當前列、自己不保存任何計數器、鎖定、
cooldown 或投票狀態；`ear_l`、`ear_r`、`yaw`、`pitch` 則是純單幀值。

**2. 時間戳不是等距的。**
手機錄的影片為變動幀率，實測間隔混合 33ms 與 34ms，另有少數更大的間隔。
換算延遲時間時要用 `timestamp_ms` 相減，不能用「幀數 × 33ms」估算。

另外，解碼器可能對極少數 sample 不輸出畫面（實測 1708 幀掉 1 幀，且每次都掉同一幀）。
這是確定性行為，不影響可重現性；掉幀數會記在 logcat 與回傳結果的 `droppedFrameCount`。

### 建立 Ground Truth

不需要逐幀人工標記。以影片時間軸粗略切出連續區段，另存成
`vision_lab_out/ground_truth_<runId>.csv`：

```csv
state,start_ms,end_ms
normal,0,20500
head_turned,20500,31900
posture_down,31900,40000
normal,40000,42200
posture_down,42200,56400
```

可用狀態是 `normal`、`eye_closed`、`head_turned`、`posture_down`、`user_missing`。
「分心／轉頭」使用 `head_turned`；Pilot v1 沒有獨立的「低頭」類別，因此低頭與趴下都先使用
`posture_down`。邊界允許是人工估計值，但第一段到最後一段必須連續、不能留時間空洞，並且要
覆蓋整支影片。

### 比較單幀與 3-of-5

比較工具直接讀同一份逐幀 CSV，不會重新執行 MediaPipe：

```powershell
dart run tool\vision_lab_compare.dart `
  vision_lab_out\frame_features_<runId>.csv `
  vision_lab_out\ground_truth_<runId>.csv `
  vision_lab_out
```

它會產生：

- `predicted_events_single_frame_<runId>.csv`
- `predicted_events_3_of_5_<runId>.csv`
- `comparison_metrics_<runId>.csv`

這裡的 3-of-5 是因果投票：只看當前列與前四列，某一狀態至少出現三次才輸出該狀態；
開頭不足五列或沒有過半時輸出 `normal`。Pilot v1 沒有遲滯、cooldown 或其他鎖定。
metrics 會列出 frame accuracy、誤報事件、漏失事件、狀態切換次數、配對事件數與平均偵測延遲；
誤報也會依四種非正常狀態分欄，方便直接讀出眨眼誤觸發數。

### 測試

以下測試同時驗證零記憶單幀規則、3-of-5、事件收合、指標計算，以及正式 app 原有時序判斷
沒有因 Lab 拆分而改變：

```powershell
flutter test --no-pub `
  test\vision\frame_classifier_test.dart `
  test\vision\vision_lab_comparison_test.dart `
  test\vision\temporal_vision_logic_test.dart `
  test\vision\companion_state_cause_test.dart
```

`vision_lab_out/` 已列入 `.gitignore`。逐幀特徵、人工 Ground Truth、預測事件與 metrics 都是
本機實驗資料，不要使用 `git add -f` 強制提交；Git 只保存可重現這些結果的程式、測試與文件。

## 專題特色

- 結合行動端即時視覺辨識與專注學習場景。
- 不只記錄時間，也嘗試判斷使用者當下狀態。
- 使用 MediaPipe 在裝置端取得臉部、眼睛與姿態特徵，減少影像上傳需求。
- 使用 Rive 動畫角色提升陪伴感，而不是單純顯示警告文字。
- 後端以正式帳號與資料庫 schema 設計，可延伸成長期專注紀錄系統。
- 語音提醒服務獨立，未來可替換為 GPT-SoVITS 或其他 TTS 模型。

## 目前限制與後續方向

- 後端目前主要完成帳號、登入、個人資料與資料庫 schema；focus session、behavior event、statistics 的完整 controller 尚待補齊。
- Flutter 部分頁面仍含 demo / placeholder 內容，可再串接實際統計 API。
- 目前 `AuthResponse` 可回傳 user id、email 與 message，但尚未建立完整 JWT 驗證流程。
- MediaPipe 判斷仍受鏡頭角度、光線、臉部遮擋與手機位置影響，需要更多實測資料調整門檻。
- Python voice service 目前偏本機測試用途，正式部署前可替換為更穩定的 TTS pipeline。
