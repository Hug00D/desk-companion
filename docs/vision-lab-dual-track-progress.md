# 視覺雙軌開發進度與交接

- 整理日期：2026-10-08。
- 本機分支：`feature/vision-lab-dual-track`；目前 HEAD：`8cd0c0e`。
- 狀態：離線工具與兩個補充候選已實作，停在 Review；尚未凍結規則、選定時間窗或接入正式 App。
- 本文件核對現有程式、Review 文件與本機既有輸出；本輪沒有執行測試、analyze、影片抽取或策略重跑。
- 下列工程驗證與辨識數字是先前執行紀錄，不是 2026-10-08 的新測試結果。

## 1. 先看結論

**已完成可比較單軌與雙軌的離線流程，並在自錄 V1／V2 上改善閱讀睡眠誤報、離席誤判與快速轉頭漏判；但低頭睡眠仍大量漏判，慢軌尚未在這兩片形成閱讀／打瞌睡標籤。**

V1／V2 已用於開發與問題分析，不能當成獨立驗證。朋友交接要求的 test6～test9 原始 CSV／GT
仍待取得，test10／test11 的凍結後獨立驗證尚未進行。正式 App 仍使用原本的視覺判斷；
本輪不修改 detector 門檻、睡眠保持、回座確認或提醒策略。

### 已完成的工作

這裡的「完成」指工具與流程可以使用，不代表所有行為都已判斷正確。

| 工作 | 目前做到什麼 |
| --- | --- |
| 固定素材比較流程 | 從影片提取原生 Face／Pose 特徵，保存 CSV 與人工 GT，同一份特徵可比較單軌與雙軌，不用每次重跑 MediaPipe |
| 離線雙軌工具 | 支援 2 秒／3 秒 PTS 視窗，輸出快軌、慢軌、最終狀態、證據、事件及 metrics |
| 保留比較基準 | 共用原 evaluator 回放；先前驗證原快軌欄位不變，可分辨改善來自哪個仲裁候選 |
| 可選候選與工程護欄 | 離席候選、五筆轉頭總分與缺臉補 50 已實作；預設不啟用，輸出防覆寫，補分不能自行觸發 |
| 既有問題查證 | 已找出空椅子 Pose 誤偵測、睡眠因追蹤中斷解除、慢軌未累積完整視窗及回座等待的原因；「找到原因」不等於「已修好」 |

### 已有改善，但仍需優化

以下成效只限 V1／V2 開發資料，尚未用新影片證明可泛化。

| 項目 | 已改善的部分 | 還要優化什麼 |
| --- | --- | --- |
| 閱讀被誤判睡眠 | V1 閱讀睡眠誤報由單軌 453 幀降為雙軌 0 幀 | 很多片段只變成 unknown；尚未可靠輸出 reading_like，不能說已分清閱讀與睡眠 |
| 離席被誤判睡眠 | V1 初始雙軌的 179 幀睡眠誤報，在離席候選後降為 0 | 開始與回座都有延遲；離席漏判仍有 32 幀，非離席誤判仍有 40 幀 |
| 快速轉頭分心 | 在離席候選上再加總分，V1 命中由 10／60 幀提高到 58／60 幀 | 回正後仍多判約 0.462 秒；不同 FPS、對答案與多工切換尚未充分驗證 |
| 部分趴下睡眠命中 | V2 三段模擬睡眠都曾被快軌趴下邏輯抓到 | 命中不持續，睡眠 Recall 只有 41.70%；追蹤消失會放掉，第三段仍延遲 3.621 秒 |

### 尚未完成，或已有程式但尚未證明有效

| 項目 | 實際狀態 | 下一步 |
| --- | --- | --- |
| 慢軌真正區分閱讀／低頭睡眠 | 分類器與單元測試已存在，但 V1／V2 的 reading_like、drowsy_like 皆為 0；實際辨識效果尚未成立 | Review 觀察窗累積、快軌清除歷史及可用眼睛／姿勢證據，不是再把低頭深度直接當睡眠 |
| 靜止低頭睡眠與持續保持 | 可局部由趴下命中，但看不到眼睛且姿勢不變時，仍無可靠區分與持續判斷 | 先定義資料中斷、真正回正與實際離席的保持／解除契約，再修改及驗證 |
| 指定資料比較與規則凍結 | test6 驗收、test6～test9 完整比較未完成，2 秒／3 秒尚未選定 | 取得指定 CSV／GT，完成比較與 Review 後才凍結 |
| 獨立驗證 | test10／test11 尚未開始；V1／V2 不能替代 | 使用凍結後的新素材，先確認 GT，再評估一次，不用同批驗證資料反覆調參 |
| 正式 App 接入及自然使用 | 雙軌尚未接入手機正式判斷／提醒，沒有雙軌自然使用驗收結果 | 獨立驗證通過後才接 feature flag，再驗證提醒冷卻、手機負擔及 45～60 分鐘體驗 |

**建議優先順序：先處理睡眠為何中途解除，再 Review 慢軌為何沒有形成有效輸出，最後才調整回座與分心解除延遲。**
這些是待確認的演算法工作，不屬於免測修改；本輪只完成工作盤點與文件整理。

## 2. 文件閱讀順序

1. 本文件：目前進度、結果、限制、下一步及 GitHub 提交範圍。
2. [開發交接清單](vision-lab-dual-track-handoff.md)：原任務 0～4 與驗收條件；不是已完成清單。
3. [研究計畫](vision-lab-dual-track-research-plan.md)：研究目的、通過條件及 test10／test11 規劃。
4. [任務 1 Review](vision-lab-dual-track-task1-review.md)：初始雙軌規則與工具工程驗證。
5. [離席候選 Review](vision-lab-presence-context-review.md)、[分心總分 Review](vision-lab-head-score-sum-review.md)：補充候選及限制。
6. [測試紀錄](vision-lab-test-log.md)、[README](../README.md)：歷次結果、素材準備及命令。

舊 Review 中的分支、日期、測試數量與「尚未提交」是當時快照。最新整體停止點以本文件為準；
未來 commit／push 後，應更新實際交付的 commit，不將本次快照當作永久狀態。

## 3. 任務進度

| 階段 | 目前狀態 | 已完成／待補 |
| --- | --- | --- |
| 任務 0：安全起點 | 已有完成紀錄 | 建立分支；修改前指定的 51 項測試通過 |
| 任務 1：離線雙軌工具 | 工具完成，驗收仍待補 | 純 Dart 分類器、共用 replay、報告及測試已完成；指定的真實 test6 重跑尚未完成，Review 尚未結案 |
| 自錄 V1／V2 比較 | 已有開發結果 | 同一份特徵比較單軌、2 秒與 3 秒雙軌；不替代任務 2 |
| 補充：離席軌跡候選 | 已實作、待 Review | CLI 明確加 `--presence-context` 才啟用 |
| 補充：分心總分候選 | 已實作、待 Review | CLI 同時加 `--presence-context --head-score-sum` 才啟用 |
| 任務 2：test6～test9 比較 | 尚未完成 | 本機缺四支指定影片的原始 CSV／GT，未選出 2 秒或 3 秒，也未凍結勝出規則 |
| 任務 3：test10／test11 | 尚未開始 | 先凍結規則，再收集未參與開發的影片與人工 GT |
| 任務 4：正式 App | 未接入 | 必須先通過獨立驗證並取得同意；正式預設不得直接替換 |

### 目前程式怎麼跑

```text
Android 原生 MediaPipe 提取 Face／Pose 特徵
  -> 保留 frame_features.csv（真實影片 PTS）
  -> 共用正式 CompanionStateEvaluator 回放，保存 fast_status／fast_cause
  -> 2 秒或 3 秒慢軌 + 可選離席／分心候選
  -> final_state、逐幀證據、事件與 metrics
```

這是離線研究流程，不是手機同時跑兩套 MediaPipe。CLI 不重抽影像，正式 App 尚未使用雙軌候選。
原快軌欄位保留不等於最終結果不變：新候選介入的是 `final_state`。

慢軌支援 `reading_like`、`drowsy_like`、`unknown_low_head`；`none` 表示尚未形成標籤，
也可能是優先分支清除了觀察窗，不能解讀為已判定清醒。`drowsy_like` 是疑似疲勞風險，
不是生理睡眠證明，也沒有另一個必然將它升級為 `sleeping` 的步驟。

### 程式地圖

| 檔案 | 用途 |
| --- | --- |
| [dual_track_context_classifier.dart](../lib/vision/dual_track_context_classifier.dart) | 慢軌時間窗、資料品質與最終仲裁 |
| [vision_lab_replay.dart](../lib/vision/vision_lab_replay.dart) | 共用 CSV 解析及正式 evaluator 回放 |
| [dual_track_lab_report.dart](../lib/vision/dual_track_lab_report.dart) | 睡眠逐幀／事件指標、閱讀誤報及 unknown |
| [disappearance_context_classifier.dart](../lib/vision/disappearance_context_classifier.dart) | 消失前相對下降、側向離席、保持及回座確認 |
| [head_offset_detector.dart](../lib/vision/head_offset_detector.dart) | 可選五筆總分；預設仍走原 3-of-5 |
| [vision_lab_dual_track.dart](../tool/vision_lab_dual_track.dart) | 離線 CLI；必要參數與輸出防覆寫 |
| [vision_lab_replay_companion.dart](../tool/vision_lab_replay_companion.dart) | 單軌 baseline CLI |

## 4. 已有資料與結果

V1 為 1874 幀，V2 為 2163 幀。原始影片放 `assets/testVideos/`，H.264 SDR 相容副本放
`assets/testVideos/playback/`。影片與 `vision_lab_out/` 不提交 Git；人工 GT 在觀看本次比較結果前
由使用者確認，後續沒有依預測結果修改。GT 時間邊界是人工近似值，仍保留轉場錯誤。

| 資料 | 主要人工標記 |
| --- | --- |
| V1 | 閱讀 4～16、23～27、29～39 秒；分心 47～49 秒；離席 52～58 秒；42.5～43 秒為眨眼，無睡眠正例 |
| V2 | 閱讀 7～14、16～21、24～32 秒；模擬低頭睡眠／趴下 44～54、60～63、64～68 秒 |

睡眠計分 GT 只接受 `normal`／`reading`／`sleeping`；分心與離席另留行為 GT，不直接送進睡眠計分器。
雙軌最終睡眠正例為 `sleeping`／`posture_down`／`drowsy_like`。睡眠 GT 中的 unknown 仍算 FN，
不得排除缺臉、遮擋或 unknown 後才報成效。

### 睡眠與閱讀

下列幀數在 2 秒／3 秒版一致；不同時間窗的 unknown 與狀態時間線不一定相同。

| 指標 | 單軌 baseline | 初始雙軌 | 加離席候選 | 再加分心總分 |
| --- | ---: | ---: | ---: | ---: |
| V1 睡眠誤報 FP | 638 | 179 | 0 | 0 |
| V1 閱讀區間睡眠誤報 | 453 | 0 | 0 | 0 |
| V2 睡眠命中 TP | 211 | 210 | 211 | 211 |
| V2 非睡眠區間誤報 FP | 37 | 0 | 5 | 5 |
| V2 睡眠漏判 FN | 295 | 296 | 295 | 295 |
| V2 睡眠 Recall | 41.70% | 41.50% | 41.70% | 41.70% |

最新候選的 V2 Precision 為 97.69%，但 Recall 只有 41.70%；三段睡眠各有重疊命中，
不代表整段都有被偵測到。第三段開始延遲約 3.621 秒，回正後還有 5 幀睡眠誤報。
兩片的慢軌 `reading_like`、`drowsy_like` 都是 0 幀：擋掉弱睡眠誤報不等於已可靠辨識閱讀。

### 離席與分心

| 項目 | 已觀察結果 | 尚未解決 |
| --- | --- | --- |
| V1 離席 | 加離席候選後，睡眠誤報 179→0；離席 GT 漏判 180→32 幀 | 最終離席為 53.095～59.362 秒；GT 是 52～58 秒，非離席區間仍有 40 幀被判離席 |
| V1 快速轉頭 | 在離席候選上再加總分，分心命中 10→58／60 幀、漏判 50→2、非分心誤報 14→13 | 最終分心為 47.095～49.462 秒，回正後仍延續約 0.462 秒 |
| V2 睡眠判離席 | 加離席候選後 146→0 幀 | 部分只是改成 unknown，不是全部改對睡眠 |

分心候選只保存最近五筆：總和至少 275，且至少兩筆真實分數達 55。缺臉補 50 必須有近期真實
轉頭證據、可靠 Pose，且沒有離席／下降／強趴下線索；純補分不能自行觸發，最多橋接兩秒。
V1 使用 50 筆補分，V2 為 0；五筆視窗仍受取樣頻率影響，也不能可靠區分快速對答案與分心。

最新 unknown 幀數：2 秒版 V1／V2 為 693／708，3 秒版為 604／618。
不能只因 3 秒 unknown 較少就選它，較長視窗也會延後進入 unknown。目前未選定勝出時間窗。

### 既有輸出來源（僅本機）

| 目錄 | 用途 |
| --- | --- |
| `vision_lab_out/comparison_20261004_233819/` | 單軌與初始雙軌比較 |
| `vision_lab_out/presence_context_20261005/` | 離席候選與模式關閉回歸 |
| `vision_lab_out/head_score_sum_20261005/final/` | 最新採用結果、兩次輸出與 `review_summary.json` |
| `vision_lab_out/head_score_sum_20261005/final/low_head_track_comparison.md` | 本機每次低頭的快／慢／最終時間對照 |

分心結果須讀 `final/`，不要使用其上層被否決的初跑輸出。本文件與各 Review 保存可提交的結果摘要；
clone 專案不會取得原始影片、CSV 或本機報告，重現真實影片結果需另外交接素材。

## 5. 目前最重要的未解問題

### P1：追蹤中斷，卻解除既有睡眠狀態

V2 第一次模擬睡眠是 44～54 秒。快軌命中來自 `postureDown`，不是閉眼 fatigue＋低頭的 `drowsy`。

| 時間 | 查到的條件與輸出 |
| --- | --- |
| 48.438 秒 | 最後一筆通過雙軌幾何品質檢查的 Pose |
| 48.539、48.876 秒 | 原始 Pose 偶爾為 true，但肩寬太小，不通過可靠幾何檢查 |
| 48.944 秒 | 距可靠 Pose 已超過 500 ms，`sleep_supported=false`，最終輸出降為 `unknown_low_head` |
| 49.720 秒 | 臉與 Pose 同時消失達連續 25 幀，原 evaluator 解除趴下 latch，快軌轉 `userMissing` |

沒有在這兩個解除時間取得「使用者已抬頭回正」的證據。解除前約 99.56 的趴下分數是沿用的分數，
不是每幀都有新量測。unknown 表示證據不足，不等於清醒；但原快軌直接判離席不符合這段人工 GT。

根因對應 [缺臉情境的 sleepSupported](../lib/vision/disappearance_context_classifier.dart)、
[正式 evaluator 的全消失解除](../lib/vision/companion_state_evaluator.dart) 與
[趴下 detector 的缺 Pose 保持期限](../lib/vision/posture_down_detector.dart)。
**本輪只整理原因，尚未修改保持／解除規則。** 不能只把保持時間延長就宣稱解決，還要避免空椅子長期保持睡眠。

### P2：慢軌在睡眠片段沒有累積完整觀察窗

V2 第一段在 44.467 秒只累積 367 ms；44.500 秒進入快軌強趴下優先分支後清除慢軌 episode。
2 秒版三段睡眠中，慢軌累積最大值為 367、1802、200 ms，均不足 2000 ms，三段 `slow_state` 全是 `none`。
最終睡眠正例來自快軌／消失仲裁，不能說是慢軌成功判出睡眠。

需 Review「輸出優先」是否必須同時「清掉觀察歷史」，並分開檢查資料品質與時序累積。
不能只把漏判歸因於沒有先閉眼，或認為低頭睡覺必須持續上下晃動。

### P3：眼睛證據不足，靜止低頭仍難區分

V2 第一次模擬睡眠最後有眼部數值是在 44.433 秒，44.467 秒起缺臉。
正式閉眼路徑未累積到三次閉合確認，慢軌也未形成「正坐可靠閉眼至少 300 ms，隨後下降」的條件。
缺眼睛不能補成閉眼；保持同一個低頭姿勢可能是閱讀，也可能是模擬睡眠，現有特徵不保證能區分。

### P4：回座解除仍有延遲

V1 人工回座約 58 秒，Face 到 58.862 秒才重新出現，再等 500 ms 回座確認，59.362 秒才解除離席。
要分開看「模型重新抓到臉的延遲」與「程式確認等待」，不能把全部 1.362 秒都歸因於防抖。
是否縮短等待、採立即解除或其他條件尚未決定；這屬於行為修改，不是文件便利性修改。

## 6. 既有工程驗證與本輪範圍

| 時間／階段 | 當時紀錄 |
| --- | --- |
| 2026-10-02 任務 1 | 全部 Vision 90 項通過；新增 26 項；合成 fixture 與共用 replay 回歸一致 |
| 2026-10-05 離席候選 | 全部 Vision 113 項通過；新增 22 項；兩種時間窗重跑一致，模式關閉結果不變 |
| 2026-10-05 分心候選 | 全部 Vision 139 項通過；新增 26 項；修改的四個 Dart 檔 analyze 無問題 |
| 分心候選可重現性 | 12 份新 CSV 重跑一致；24 份原／只開離席輸出不變；8074 次快軌欄位核對一致 |

先前完整 analyze 仍有登入頁既有 13 項 `withOpacity` 棄用提示，不宣稱整個專案零 issue。
工程測試證明格式、時序邊界及回歸，不證明真實睡眠辨識已達標，也不證明 MediaPipe 重抽影片完全一致。
2026-10-08 僅做文件及 Git 狀態／忽略規則檢查；沒有新增測試通過紀錄。

## 7. 下一步與不跑測試的便利性整理

演算法下一步：先 Review P1、P2 的保持與仲裁契約，再決定修改範圍；若改動，需做聚焦單元測試與
既有 CSV 回歸，不必立即重拍影片。取得 test6～test9 後完成原驗收，確認規則再凍結；
test10／test11 必須使用未參與調參的新素材，通過後才討論正式 App。

本輪已補進度入口、已知問題、結果摘要與提交範圍。下列項目是**待選工作，尚未實作**，只整理文件或
既有資料，不改判斷行為，因此可先做，不需執行 App 或重跑測試：

| 選項 | 可先做的內容 | 便利性 |
| --- | --- | --- |
| A：CSV 中文欄位字典 | 逐項說明快軌、慢軌、最終狀態、品質、真實分數／補分及單位 | 朋友不用讀 Dart 才能看懂結果 |
| B：人工 GT 範本 | 分開提供活動時間段與睡眠計分模板，附眨眼、轉場及時間單位說明 | 下次拍影片能直接填，不靠聊天訊息交接 |
| C：完整錯誤時間表 | 從現有輸出讀取 V1／V2 錯判區間，整理成可提交 Markdown，標明策略版本與來源 | 不必重新找本機報告或捲聊天紀錄 |
| D：素材交接索引 | 整理檔名、用途、原片／相容版、CSV／GT 對應與既有轉檔紀錄 | 朋友拿到素材後比較容易對上正確版本；不把人像影片公開提交 |
| E：操作速查文件 | 將素材準備、CSV 抽取、單軌與各雙軌模式整理成一頁命令範例 | 減少在 README 與 Review 之間來回找命令 |

「不用重新錄影／抽特徵」不等於「改程式不用驗證」。一鍵執行腳本、CLI 參數調整、CSV 新診斷欄位、
睡眠保持、慢軌歷史保留、回座解除、補分門檻或正式 App 接入，仍需相應驗證；本輪不先做。

## 8. GitHub 提交注意事項

截至本次整理，雙軌工具與 Review 多為未追蹤檔，其他相關檔案有未提交修改；本輪沒有 stage、commit 或 push。
先選擇交付「只有進度文件」或「進度文件＋可執行工具」，不要用 `git add .` 混入其他工作。

### 建議提交分組

| 分組 | 檔案範圍 |
| --- | --- |
| 進度與研究文件 | 本文件、`vision-lab-dual-track-handoff.md`、`vision-lab-dual-track-research-plan.md`、三份候選／任務 Review；README 與 test log 的相關段落 |
| 離線工具 | `lib/vision/{vision_lab_replay,dual_track_context_classifier,dual_track_lab_report,disappearance_context_classifier,head_offset_detector}.dart`、`tool/{vision_lab_dual_track,vision_lab_replay_companion}.dart` |
| 工程測試 | `test/vision/{dual_track_context_classifier,disappearance_context_classifier,head_offset_score_sum}_test.dart`、`test/fixtures/vision/dual_track_{features,truth,replay_baseline}.csv` |
| 影片準備支援（另 review） | `.gitignore`、`tool/prepare_vision_lab_videos.ps1`、`lib/main_vision_lab.dart`、`lib/vision/vision_channel.dart`、`test/vision/vision_channel_test.dart`、Android `MainActivity.kt`、`pubspec.yaml` 中的影片 asset 變更 |

`lib/api/assistant_api.dart`、`lib/screens/face_detection_screen.dart`、`steps/local_server_steps` 的目前修改
不屬於雙軌離線工具交付；`pubspec.lock` 及 `pubspec.yaml` 需逐段確認，不自動整份收進此 commit。
只有文件 commit 不會讓 GitHub 上的 CLI 自動存在，若要朋友能執行，需把上述工具及測試也提交。

只提交文件時，可在專案根目錄人工確認後使用以下命令；這是操作範例，本輪未執行：

```powershell
git status --short
git diff -- README.md docs
git add -- docs/vision-lab-dual-track-progress.md docs/vision-lab-dual-track-handoff.md docs/vision-lab-dual-track-research-plan.md docs/vision-lab-dual-track-task1-review.md docs/vision-lab-presence-context-review.md docs/vision-lab-head-score-sum-review.md
git add -p -- README.md docs/vision-lab-test-log.md
git diff --cached --stat
git diff --cached --check
git diff --cached
git commit -m "docs: summarize dual-track vision progress"
git push -u origin feature/vision-lab-dual-track
```

原始影片、人像截圖、真實逐幀 CSV／GT、`vision_lab_out/`、FFmpeg 二進位及語音模型／runtime 不提交。
`assets/testVideos/` 與 `vision_lab_out/` 已受 ignore 保護；不要使用 `git add -f`。
可提交的 `test/fixtures/vision/dual_track_*.csv` 是合成工程 fixture，與真實量測 CSV 分開。
因影片不在 Git，clone 後需另放相容素材並確認 `pubspec.yaml` 所列本機 asset 存在，才能啟動 Lab。

## 9. 對外／面試摘要

> 我保留原本即時判斷為快軌，新增依影片 PTS 運作的 2／3 秒慢軌，以及可選的離席軌跡與轉頭總分仲裁。
> 目前完成離線工具與先前的工程回歸驗證，在兩支開發影片上降低閱讀睡眠誤報並補回部分快速轉頭。
> 但慢軌尚未在這些影片形成閱讀／打瞌睡標籤，低頭睡眠 Recall 仍約 41.7%，保持與解除條件仍需研究。
> 尚未通過獨立驗證，因此未接入正式 App，也沒有宣稱能判定生理睡眠。
