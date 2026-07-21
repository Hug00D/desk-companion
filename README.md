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

### 4. 啟動語音服務, optional

```powershell
python backend\python_voice_service\app\main.py --host 0.0.0.0 --port 8001
```

Flutter emulator 預設會呼叫：

```text
http://10.0.2.2:8001
```

實體手機可用：

```powershell
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.23:8080/api/v1 `
  --dart-define=VOICE_SERVICE_URL=http://192.168.1.23:8001
```

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
