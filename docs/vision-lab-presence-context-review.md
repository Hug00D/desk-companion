# 離席消失軌跡：離線候選 Review

- 日期：2026-10-05；branch：`feature/vision-lab-dual-track`，尚未 commit／push。
- 目的：先處理 V1 離席被判睡眠，檢查消失前的軌跡是否能改進仲裁。
- 範圍：只接雙軌 CLI，必須明確加 `--presence-context`；不改正式 evaluator、MediaPipe 或 App。
- 資料角色：既有自錄 V1／V2 的開發資料，不是獨立驗證。GT 保持原本使用者確認版本。

## 已查證的原因

V1 的 `face_detected` 在 52.595 秒變成 false，58.862 秒才再次變成 true。
這段時間 Pose 大多仍輸出 true，包含高 visibility 的鼻子與肩膀，初期還有超出影像的座標。
回看第 54 秒的影片確認是空椅子；因此不能只以 Pose boolean 或 visibility 認定使用者還在座位。
正式 `PresenceDetector` 只有臉與 Pose 都不存在才回傳 away；正式 evaluator 又有趴下 latch，
結果離席區段繼續輸出 sleeping／postureDown。既有雙軌保留快軌優先序，所以也保留此誤報。

V1 離席前鼻子的絕對 Y 確實增加，但同時頭與肩膀向左側離開畫面。
「絕對 Y 下降就算睡眠」不能區分頭相對身體下墜與整個身體移動。
這輪不把只有下降軌跡的輸入直接當睡眠：先保留 sleepCandidate，再要求獨立姿勢支持。

## 修改與規則

| 檔案 | 修改 |
| --- | --- |
| `lib/vision/disappearance_context_classifier.dart` | 純 Dart 消失前軌跡、離席保持與回座確認 |
| `lib/vision/dual_track_context_classifier.dart` | 可選的最終仲裁，原快軌欄位保留 |
| `tool/vision_lab_dual_track.dart` | `--presence-context` 旗標、獨立 `_presence` 輸出與診斷欄位 |
| `test/vision/disappearance_context_classifier_test.dart` | 22 項邊界、證據、回歸與 CLI 測試 |

所有時間判斷使用 PTS，沒有影片名稱、時間位置或影片專屬門檻。

| 項目 | 起始候選規則 |
| --- | --- |
| 可用 Pose | 沿用雙軌現有幾何／visibility 檢查，包括點在畫面內與肩寬 |
| 可見歷史 | 臉可見時保留最近 1000 ms 的可靠 Pose；至少 300 ms 跨度，末樣本距消失不超過 500 ms |
| 相對下降 | `(鼻子 Y - 兩肩平均 Y) / image_height` 增加至少 0.06；單純全身垂直平移不成立 |
| 側向離開 | 鼻子接近左右 15% 邊界，鼻子同向移動至少影像寬度 20%，肩膀中心同向移動至少 15% |
| 失蹤確認 | 臉持續消失 500 ms；此前 pending 不繼承睡眠。單純轉頭、Pose 留在原位不算側向離席 |
| 離席成立 | 有側向離開證據；或有可靠可見歷史、無相對下降，且臉與 Pose 都持續消失 500 ms |
| 保持離席 | 成立後保存該次離開證據；之後空椅子的 Pose 不解除離席，也不建立新的可見歷史 |
| 睡眠支持 | 消失前相對下降＋既有強趴下確認＋最近 500 ms 仍有可靠 Pose；下降本身不足以成立 |
| 缺證據 | unknown，不能把缺資料當作沒有下降；不自行推論睡眠或離席 |
| 回座 | 臉連續回來 500 ms 才清除此失蹤事件；不要求抬頭，以免低頭回座無法恢復 |
| 斷訊／reset | 相鄰 PTS 超過 500 ms 清除歷史，不用斷訊補滿確認時間；`reset()` 清除所有狀態 |

逐幀額外欄位：`presence_context`、`presence_reason`、`face_missing_ms`、
`loss_history_reliable`、`side_exit_evidence`、`relative_descent_evidence`、`sleep_supported`。
`unknown_low_head` 在此模式也表示消失情境仍不確定，不代表已確認頭部處於低位。
此模式是新的實驗仲裁，不是只更改 2 秒／3 秒視窗。

## 重跑結果

輸出在 `vision_lab_out/presence_context_20261005/run_a/`；`run_b/` 為同一輸入重跑。
2 秒與 3 秒版的下列睡眠／離席結果相同；unknown 幀數隨視窗不同。

| 指標 | 原雙軌 | 加離席候選 |
| --- | ---: | ---: |
| V1 睡眠誤報幀數 | 179 | 0 |
| V1 離席 GT 漏判幀數（共 180 幀） | 180 | 32 |
| V1 非離席 GT 被判離席 | 0 | 40 |
| V2 睡眠 GT 被判離席 | 146 | 0 |
| V2 睡眠命中幀數 | 210 | 211 |
| V2 睡眠漏判幀數 | 296 | 295 |
| V2 非睡眠誤報幀數 | 0 | 5 |
| V2 睡眠 Recall | 41.50% | 41.70% |
| V2 睡眠 Precision | 100% | 97.69% |

- V1 52.595～53.095 秒為 pending；53.095～59.362 秒判離席。
  相對 GT 52 秒開始離席，仍有約 1.095 秒確認延遲；相對 58 秒回座，仍延續約 1.362 秒。
  不能因為睡眠誤報為 0，就宣稱離席時序全部正確。
- V2 62.254～62.521 秒原本趴下卻判分心，此模式未再輸出分心；缺可靠姿勢時改為 unknown。
  不代表消失的睡眠幀全部判對，整體 Recall 仍低。
- V2 新增 5 幀睡眠誤報在約 63.020～63.188 秒回正邊界；保留失敗結果，不改 GT 美化分數。
- V2 三段睡眠延遲由 `500;729;3621` 變為 `997;729;3621` ms，第一段因確認等待變慢。
- unknown：2 秒版 V1 677→740、V2 397→708；3 秒版 V1 588→651、V2 307→618。
  減少錯判離席的部分輸出仍只是 unknown，不能解讀為已可靠辨識睡眠。

## 驗證與停止點

- 全部 `flutter test --no-pub test/vision`：113 項通過，其中本輪新增 22 項。
- 本輪 4 個 Dart 檔靜態分析：無問題。
- 開啟模式：兩片、兩種視窗共 12 份重跑 CSV 的 SHA256 完全一致。
- 關閉模式：重跑真實 V1／V2 兩種視窗，12 份輸出與 2026-10-04 原雙軌逐位元一致。
- 新模式的逐幀 frame／PTS／fast status／fast cause 與原雙軌完全相同。
- 沒有重抽 MediaPipe、覆寫原始特徵／GT、啟用正式 App 或新增提醒。
- 狀態：候選可供 Review，未凍結成正式方案；test6～test9 仍未補齊，獨立驗證尚未進行。

下一步檢查不同方向離席、轉頭但仍坐著、低頭閱讀時短暫缺臉、低頭回座等額外素材。
低 visibility、背景誤偵測、多人的切換、正前方／後方離開但仍有殘留 Pose，
以及消失前完全沒有可靠歷史的情況都不保證能分類；證據不足維持 unknown。
