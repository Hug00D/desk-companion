# Desk Companion 語音系統問題與修改紀錄

最後更新：2026-08-04

## 文件用途

本文件是語音功能的單一維護紀錄，涵蓋喚醒詞、STT、本地指令、LLM、Python 語音服務、GPT-SoVITS、音檔下載、播放器與對話氣泡。

之後只要修改上述流程，必須在本文件新增或更新一筆紀錄，至少包含：

1. 日期與問題編號。
2. 使用者看到的症狀。
3. 已確認的根因，不以猜測代替。
4. 修改檔案與實作方式。
5. 驗證方法、測試環境與結果。
6. 實測成效、殘留風險與是否需要回退。

狀態定義：

- `已完成`：程式與自動測試均完成，且至少通過一次實際裝置或模擬器驗證。
- `待實測`：程式與自動測試完成，尚待 App 實際流程驗證。
- `進行中`：正在修改或測試。
- `未處理`：已確認問題，但尚未排入修改。
- `觀察中`：目前未重現，保留監控與紀錄。

## 目前語音流程

```text
喚醒詞「路米娜」
→ 播放本地確認音
→ Android STT 收音與轉文字
→ 本地指令判斷
→ 本地指令直接執行，聊天內容送 LLM
→ LLM 回覆送往 Python 語音服務
→ GPT-SoVITS 生成完整 WAV
→ Flutter 下載並驗證音檔
→ 單一 AudioPlayer 開始播放
→ 播放啟動時同步顯示相同文字氣泡
→ 播放完成後恢復喚醒詞監聽
```

## 問題與修改紀錄

### VOICE-001：WAV 下載途中連線中斷

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：Python 顯示 `audio served`，Flutter 連續出現 `Connection closed while receiving data`，最後只有文字沒有聲音。
- 根因：第一輪先排除了長生命週期 Client 與 HTTP/1.0 問題；實測仍重現後，以同一個 `requestId` 對照確認 Python 已寫出完整 bytes，但 Android `HttpClient` 會將 `BaseHTTPRequestHandler` 的大型 `Content-Length + Connection: close` 回應判成提早關閉。
- 修改：
  - WAV 每次下載與每次重試建立新的 `http.Client`，完成後立即關閉。
  - Flutter 與 Python 均傳送 `Connection: close`。
  - Python 改用 HTTP/1.1；JSON 保留 `Content-Length`。WAV 曾改用 close-delimited body，但 App 實測仍會隨機少 1～6 bytes，因此改成標準 `Transfer-Encoding: chunked`，用終止 chunk 明確標示音檔結尾；`X-Audio-Length` 繼續提供預期大小。
  - chunked 版 App 實測回報 `Failed to parse HTTP`，確認手刻 framing 仍不可靠；移除 `BaseHTTPRequestHandler`，改由 FastAPI + Uvicorn 的 `FileResponse` 負責標準檔案串流與 HTTP framing。
  - Flutter 不再強制傳送 `Connection: close`；每次請求仍使用獨立 Client，並在完整讀取 response 後關閉。
  - Flutter 同時核對 `X-Audio-Length` 與 WAV 內部 RIFF 宣告長度；即使傳輸被截斷，也不會把壞檔交給播放器。
  - Python 音檔 URL 改為相對路徑，由 Flutter 根據設定的服務位址解析。
- 驗證：2026-08-04 App 實測顯示 close-delimited 第一輪少 1 byte 後重試成功；第二輪三次分別少 4、6、3 bytes。手刻 chunked 版則明確回報 `Failed to parse HTTP`。改用 Uvicorn 後，Python 8 項測試全數通過，包含以真實 Uvicorn socket 完整傳送 400,004 bytes、音檔刪除及併發生成排隊；Dart 靜態分析與 Python 語法檢查通過。Flutter test runner 被 Android Studio 的既有 Flutter daemon 卡住，尚未取得單元測試執行結果。
- 成效：完整性驗證已成功阻止破損 WAV 進入播放器；HTTP framing 已交由成熟 ASGI server 管理，待 App 連續至少兩輪對話實測。

### VOICE-002：喚醒、STT、LLM、TTS callback 互相競爭

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：提醒與喚醒詞接近同時觸發後，STT 或喚醒監聽不再恢復；語音與氣泡不同步。
- 根因：互動狀態由多個可變 Boolean 分散控制，且確認音與聊天語音使用不同播放器及完成 callback。
- 修改：
  - 以 `_VoiceSessionPhase` 統一管理喚醒、收音、送出、LLM、TTS 與播放階段。
  - 所有輸出聲音改用單一 `AudioPlayer` 與單一音訊焦點。
  - 每次播放只建立該次使用的完成監聽，播放後立即取消。
  - STT 最終結果先進入 submitting 狀態，避免 `done` callback 過早恢復喚醒詞。
- 驗證：相關 Flutter 檔案靜態分析通過。
- 成效：狀態競爭路徑已收斂，待提醒、喚醒與聊天交錯實測。

### VOICE-003：聊天氣泡早於語音或重複出現

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：LLM 文字先顯示，GPT-SoVITS 完成後氣泡再次出現並播放語音。
- 根因：文字呈現與語音下載、播放使用兩條獨立流程。
- 修改：聊天語音先完成生成與下載；只有 `AudioPlayer.play()` 成功後才在同一 callback 顯示氣泡與 Snackbar。生成失敗時才退回純文字。
- 驗證：Flutter 靜態分析通過。
- 成效：程式路徑已保證正常語音回覆只呈現一次，待實際播放確認時間感受。

### VOICE-004：損壞或非 WAV 回應可能進入播放器

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：長度正確但內容錯誤的回應，可能直到播放器才失敗；Python 可能先發布壞檔才驗證。
- 根因：Flutter 只檢查狀態碼、非空與 `Content-Length`；GPT-SoVITS 輸出先 `replace()` 再以 `wave.open()` 驗證。
- 修改：
  - Flutter 驗證 `Content-Type`、至少 44 bytes、`RIFF` 與 `WAVE` 標頭。
  - Python 在暫存檔上完成 WAV 與 duration 驗證後才原子替換正式檔。
  - Python 生成入口捕捉所有一般例外，統一回傳結構化 503 錯誤。
- 驗證：Python 測試確認損壞 GPT-SoVITS 回應會拋出結構化錯誤，且正式檔與暫存檔都不會殘留；Flutter 已新增 MIME、長度及 RIFF/WAVE 測試案例，相關檔案靜態分析通過。
- 成效：自動測試通過，待 App 實際播放正常與損壞音檔情境。

### VOICE-005：Python 忙碌時靜默丟掉新語音

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：LLM 有文字，但 Python 回傳 `generation_already_in_progress` 或 `generation_debounced`，App 沒有聲音。
- 根因：服務用 202 `skipped_debounce` 代替排隊。
- 修改：移除靜默跳過與三秒 debounce；改成單一生成槽及 15 秒有界等待。等待逾時回傳明確 `generation_queue_timeout`，不再偽裝成成功。15 秒排隊加上 180 秒模型時限仍小於 Flutter 的 200 秒總時限。
- 驗證：兩個真實 HTTP TTS 請求同時送出，兩者皆取得 200 與各自的 requestId，最大同時生成數保持為 1；程式碼已無 `generation_already_in_progress`、`generation_debounced` 或 `skipped_debounce`。
- 成效：自動併發測試通過，待實際連續聊天與多裝置測試。

### VOICE-006：缺少跨層 requestId 與健康資訊

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：無法從 Log 判斷同一句話卡在生成、下載或播放；實體手機使用錯誤位址時只能看到沒聲音。
- 根因：Flutter 的 request ID 沒送到 Python，且 App 啟動時不檢查 `/health`。
- 修改：
  - 每次 TTS 帶唯一 `requestId`，Python 回傳並寫入生成 Log，Flutter 下載與播放 Log 使用同一 ID。
  - `/health` 增加 GPT-SoVITS、生成中與等待數量。
  - App 啟動時輸出語音開關、平台、服務位址與健康結果。
  - 語音 Demo 面板顯示連線與 GPT-SoVITS 狀態，提供重新檢查按鈕。
- 驗證：Python 8 項語音服務測試全數通過；Flutter requestId、健康解析與 WAV 驗證測試已新增，相關檔案靜態分析通過。
- 成效：Log 與 UI 已具備定位生成、下載、播放與服務位址的資訊，待模擬器與實體手機確認顯示。

## 尚未處理與後續規劃

### VOICE-007：生成工作無法真正取消

- 狀態：`未處理`
- 現況：Flutter 已序列化互動，能避免同一畫面重複送出；但 App timeout、離開頁面或中止下載後，GPT-SoVITS 仍可能在背景占用 GPU。
- 後續：需要工作式 API、取消狀態與可中止的 worker/subprocess。GPT-SoVITS 同步 GPU 推論若沒有取消 API，不能宣稱已真正取消。

### VOICE-010：不同網路階段共用過長 timeout

- 狀態：`待實測`
- 現況：TTS 生成總時限維持 200 秒，但 WAV GET 已拆成每次最多 20 秒，最多三次獨立連線重試；健康檢查為 5 秒。
- 成效：下載斷線不再可能單次等待 200 秒，待實際斷網與恢復測試。

### VOICE-008：實體手機不能使用模擬器預設位址

- 狀態：`觀察中`
- 現況：預設 `VOICE_SERVICE_URL=http://10.0.2.2:8001` 只適用 Android 模擬器。
- 使用方式：實體手機必須以 `--dart-define=VOICE_SERVICE_URL=http://<LAN或Tailscale-IP>:8001` 執行。
- 後續：正式版改由後端設定或 App runtime 設定提供，不應依賴重新編譯。

### VOICE-009：語音播放政策尚未完全統一

- 狀態：`觀察中`
- 現況：聊天回覆使用 GPT-SoVITS；本地指令主要直接執行並顯示文字；視覺提醒使用打包 WAV。
- 後續：為 command、clarify、fallback、chat 明確定義 `speak/silent` 政策，避免使用者將設計上的靜音誤認為故障。

### VOICE-011：模型格式殘渣被送進 TTS

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：聊天回覆出現 `好 =====...`，Python 與 GPT-SoVITS 依照收到的文字生成長音檔。
- 根因：Spring Boot 只對 Ollama 回覆執行 `trim()`；Flutter 的簡短回覆 formatter 只限制句數、長度及英文，沒有移除模型思考標籤、Markdown fence 或重複分隔符號。
- 修改：Spring Boot 與 Flutter 各自加入一層模型輸出清洗；移除 `<think>`、程式碼 fence、角色標籤及三個以上的重複格式符號。清洗後若沒有內容，改用固定中文錯誤句，不再將垃圾文字送往 TTS。
- 驗證：新增 Dart 與 Java 單元測試，涵蓋 `好 =====...`、隱藏思考內容與純格式符號回覆。Java 新增的 2 項清洗測試通過，Dart 靜態分析通過；Flutter test runner 受既有 daemon 卡住並於 120 秒逾時，尚未取得 Dart 單元測試執行結果。Java 測試類別內另 2 項既有測試因本機未啟動 `localhost:11434` Ollama 而失敗，與本次清洗測試無關。
- 成效：待 App 實測確認氣泡與語音均只包含清洗後文字。

### VOICE-012：成功辨識後顯示 `error_client`

- 日期：2026-08-04
- 狀態：`待實測`
- 症狀：STT 已成功顯示中文逐字稿並送出，但畫面稍後又顯示 `語音辨識失敗：error_client`。
- 根因：對話流程完成後仍會呼叫 `SpeechRecognizer.cancel()`；若平台辨識工作階段已由 final result 結束，這個清理呼叫可能回報晚到的 client error，並覆蓋已成功的 UI 狀態。
- 修改：`stop()` 與 `cancel()` 在平台已不處於 listening 時直接返回；若 final transcript 已被接受，忽略其後晚到的 `error_client`，其他真正發生在收音階段的 client error 仍正常顯示。
- 驗證：Dart 靜態分析通過；Flutter test runner 受既有 daemon 卡住並於 120 秒逾時。待模擬器連續執行喚醒、辨識及聊天確認。
- 成效：待 App 實測確認成功逐字稿不再被晚到錯誤覆蓋。

## 每次修改後的最低驗收

1. 連續執行至少 10 次「喚醒 → STT → LLM → TTS → 播放」。
2. 每次比對 `requestId`、Content-Length、實際 bytes、WAV 標頭與播放器完成事件。
3. 測試提醒播放中喊喚醒詞，確認提醒被中斷且 STT 能開始。
4. 測試 TTS 生成期間不會重複送出或出現 `generation_already_in_progress`。
5. 測試 Python 未啟動、GPT-SoVITS 未就緒及錯誤服務位址，UI 必須顯示可理解狀態。
6. 分別測試 Android 模擬器 `10.0.2.2`、實體手機區網 IP 與 Tailscale IP。
7. 執行 Flutter 靜態分析、語音 Client 測試及 Python voice service 測試。
