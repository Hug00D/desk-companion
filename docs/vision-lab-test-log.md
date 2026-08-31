# Vision Lab 測試紀錄

本文件保存 Vision Lab 每次實驗的可讀摘要。原始逐幀資料、Ground Truth、預測事件與
metrics CSV 放在專案根目錄的 `vision_lab_out/`，並由 `.gitignore` 排除；CSV 是原始證據，
本文件則是應提交到 Git 的研究紀錄。

- 驗收範圍與停止條件：[`PILOT.md`](../PILOT.md)
- 執行與比較方式：[`README.md`](../README.md#vision-lab離線視覺量測)

## 紀錄規則

1. 每批實驗新增一節，不覆寫舊結果。
2. 一律記錄日期、影片來源、run ID、Ground Truth 規則、策略參數與使用的 CSV 檔名。
3. 「逐幀指標」與「事件指標」分開記錄：
   - Precision／Recall／F1 與 frame accuracy 是逐幀指標。
   - 誤報事件、漏失事件、狀態切換與 onset delay 是事件／時序指標。
4. Precision = TP / (TP + FP)，Recall = TP / (TP + FN)，F1 是 Precision 與 Recall 的調和平均。
5. Ground Truth 沒有某狀態的真實樣本時，該狀態的 Recall 與 F1 記為 `N/A`，不得填 0
   或宣稱模型已驗證該狀態。
6. 延遲定義為 `predicted_onset - true_onset`；負值表示模型比人工標記的起點更早觸發。

## 實驗索引

| 實驗 | 日期 | 影片數 | 比較策略 | 狀態 |
| --- | --- | ---: | --- | --- |
| Pilot v1 | 2026-08-28～2026-08-30 | 3 | 單幀 vs 因果 3-of-5 | 完成 |

---

## Pilot v1：單幀 vs 3-of-5

### 目的

確認使用相同的逐幀特徵時，因果 3-of-5 投票能否減少零記憶單幀分類造成的誤報與狀態抖動，
並量化它增加的偵測延遲。MediaPipe 每支影片只執行一次；兩種策略均從相同的
`frame_features_*.csv` 後處理產生。

### 策略設定

| 策略 | 設定 |
| --- | --- |
| 單幀 | 直接使用當前列 `raw_state`，無計數器、鎖定、遲滯或 cooldown |
| 3-of-5 | 只看當前列與前四列；同一狀態至少 3 票才輸出，視窗不足或無多數時輸出 `normal` |

狀態集合為 `normal`、`eye_closed`、`head_turned`、`posture_down`、`user_missing`。

### 執行版本與環境

- Branch：`codex/vision-lab-pilot-v1`
- Pilot v1 收尾 commit：`5ec01eb`（Document Vision Lab pilot results）
- test1／test2 抽取裝置：Pixel 6a API 31 Android 模擬器，x86_64、CPU MediaPipe
- test1／test2 使用 `VISION_LAB_ASSET` 選片參數與 pubspec asset 登錄執行；此設定納入本次
  Pilot v1 工程收尾。

### 影片與 Ground Truth

| 影片 | 專案檔案 | 拍攝來源 | Run ID | 幀數 | PTS 範圍 | Ground Truth 摘要 |
| --- | --- | --- | --- | ---: | ---: | --- |
| test | `assets/test.mp4` | 自行拍攝；iPhone 16 錄影 | `1787902528095107` | 1707 | 0–56903 ms | normal；20.5–31.9 秒轉頭／分心；32–40 與 42.2–56.4 秒姿態下降 |
| test1 | `assets/test1.mp4` | 自行拍攝；iPhone 16 錄影 | `test1_1788078623363049` | 960 | 0–32001 ms | 0–18.6 秒 normal；18.6–23 秒轉頭／分心；其餘 normal |
| test2 | `assets/test2.mp4` | 自行拍攝；iPhone 16 錄影 | `test2_1788079000832969` | 1013 | 0–33766 ms | 0–4.8 秒 normal；4.8–20 秒低頭／趴下；23.3–32.1 秒離席；其餘 normal |

三支影片皆由研究者自行使用 iPhone 16 拍攝；拍攝日期未記錄。test2 的起身過程
（20–23.3 秒）與人物已回來但臉仍不可見的區段（32.1 秒之後），依「真實人物狀態」標為
`normal`，而不是依模型是否看到臉標記。

本次原始檔案：

- `frame_features_<runId>.csv`
- `ground_truth_<runId>.csv`
- `predicted_events_single_frame_<runId>.csv`
- `predicted_events_3_of_5_<runId>.csv`
- `comparison_metrics_<runId>.csv`

### 各影片結果

| 影片 | 策略 | Frame accuracy | 總誤報事件 | 漏失事件 | 狀態切換 | 已配對／真實事件 | 平均延遲 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| test | 單幀 | 65.9% | 137 | 0 | 171 | 3 / 3 | 990.3 ms |
| test | 3-of-5 | 66.7% | 50 | 0 | 81 | 3 / 3 | 1056.7 ms |
| test1 | 單幀 | 27.1% | 14 | 0 | 27 | 1 / 1 | 101.0 ms |
| test1 | 3-of-5 | 27.2% | 10 | 0 | 19 | 1 / 1 | 168.0 ms |
| test2 | 單幀 | 74.8% | 25 | 0 | 40 | 2 / 2 | -167.0 ms |
| test2 | 3-of-5 | 75.8% | 12 | 0 | 24 | 2 / 2 | -100.5 ms |

### 三支影片合計

Frame accuracy 以 3680 幀加權；平均延遲以 6 個已配對真實事件加權。

| 指標 | 單幀 | 3-of-5 | 變化 |
| --- | ---: | ---: | ---: |
| 加權 frame accuracy | 58.2% | 58.9% | +0.7 個百分點 |
| 總誤報事件 | 176 | 72 | -104（-59.1%） |
| 閉眼誤報事件 | 50 | 39 | -11（-22.0%） |
| 漏失事件 | 0 | 0 | 0 |
| 狀態切換 | 238 | 124 | -114（-47.9%） |
| 平均 onset delay | 456.3 ms | 522.8 ms | +66.5 ms |

### 三支影片合計：逐狀態 Precision／Recall／F1

`Support` 是 Ground Truth 中屬於該狀態的幀數。下表是逐幀指標，不是事件數。

| 狀態 | Support | 單幀 P | 單幀 R | 單幀 F1 | 3-of-5 P | 3-of-5 R | 3-of-5 F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| normal | 1820 | 90.4% | 40.0% | 0.555 | 90.3% | 40.4% | 0.559 |
| eye_closed | 0 | 0.0% | N/A | N/A | 0.0% | N/A | N/A |
| head_turned | 474 | 83.0% | 55.5% | 0.665 | 83.9% | 53.8% | 0.656 |
| posture_down | 1122 | 86.6% | 79.1% | 0.827 | 86.4% | 81.3% | 0.837 |
| user_missing | 264 | 71.4% | 100.0% | 0.833 | 76.3% | 100.0% | 0.866 |

`eye_closed` 的 Ground Truth support 為 0，表示本批資料沒有把任何時間區段標成「持續閉眼」；
因此只能看出模型產生了閉眼誤判，不能由這批影片計算閉眼 Recall 或有效 F1。

### 初步觀察

> 在 3 段影片上，3-of-5 將總誤報事件從 176 次降至 72 次，閉眼誤報事件從 50 次降至
> 39 次，狀態切換從 238 次降至 124 次，漏失維持 0 次；代價是平均偵測延遲增加約
> 0.067 秒。

- 3-of-5 明顯減少事件碎裂與狀態抖動，但加權 frame accuracy 只增加 0.7 個百分點。
- test1 有 700 / 960 幀被單幀規則判為 `eye_closed`。這是持續性的單幀規則偏差，投票無法
  像處理短暫眨眼那樣消除。
- test2 的平均延遲為負值，代表預測事件比人工 Ground Truth 邊界更早開始；這可能同時受到
  粗略人工邊界與模型提早誤觸發影響，不能直接解讀成「偵測更快」。
- 本結果支持「3-of-5 可降低短暫抖動」；尚不足以宣稱整體視覺分類已達高準確率，也不足以
  評估真正閉眼事件的 Recall。

### 決策

Pilot v1 已完成，停止增加報表 UI、5-of-7、遲滯、cooldown 或批次掃描。若另開 v2，第一個
研究問題應限定為持續性 `eye_closed` 誤判，並使用新的校正影片調整規則，再用未參與調參的
影片驗證，避免在同一批資料上調參與宣稱改善。

---

## V2 診斷 1：test1 持續性閉眼誤判

### 日期與問題

- 日期：2026-08-31
- Branch：`codex/vision-lab-v2-eye-calibration`
- 問題：為什麼 test1 有 700 / 960 幀被零記憶規則判為 `eye_closed`？
- 本階段只讀取 Pilot v1 的原始 CSV，沒有修改 FrameClassifier 或正式 app。

### 三支影片的 EAR 概況

`Face + EAR` 是同時有臉且左右 EAR 完整的幀數；閉眼比例以這些幀為分母。

| 影片 | 總幀數 | Face + EAR | `raw_eye_closed` | 閉眼比例 | 平均 EAR 中位數 | 平均 EAR Q25–Q75 | abs(pitch) 中位數／Q95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| test | 1707 | 1205 | 318 | 26.4% | 0.1781 | 0.1451–0.2013 | 4.4° / 47.1° |
| test1 | 960 | 960 | 700 | 72.9% | 0.1577 | 0.1471–0.1640 | 2.4° / 4.8° |
| test2 | 1013 | 269 | 147 | 54.6% | 0.1621 | 0.1305–0.1746 | 2.2° / 33.1° |

test2 有大量趴下與離席區段，不能把上表的閉眼比例直接當正常坐姿誤判率；此表只用來比較
輸入特徵的尺度。

### test1 的 Ground Truth 分解

| Ground Truth | 幀數 | 判為 `raw_eye_closed` | 比例 |
| --- | ---: | ---: | ---: |
| normal | 828 | 691 | 83.5% |
| head_turned | 132 | 9 | 6.8% |

test1 全部 960 幀都有臉與左右 EAR，且 abs(pitch) 中位數僅 2.4°、Q95 僅 4.8°，因此持續
閉眼誤判不是缺臉、低頭或 reading-pitch 門檻縮放造成。左右眼 EAR 中位數分別為 0.1670 與
0.1477，存在明顯不對稱；右眼中位數已落在目前規則的低開眼區間。

目前 EAR 會先以 `[0.13, 0.27]` 映射到 `[0, 1]` 的開眼機率，再要求：

```text
min(left_open, right_open) < 0.18
且 average(left_open, right_open) < 0.28
```

在沒有 reading-pitch 縮放且 EAR 尚未被 clamp 的範圍內，這約等於單眼 EAR 小於 0.1552，
同時雙眼平均 EAR 小於 0.1692。test1 的正常坐姿分布大量落在這兩個門檻以下，所以形成
持續性錯誤；3-of-5 只會保留持續錯誤，無法像過濾單次眨眼一樣消除它。

### 結論與停止點

- 原因定位為固定 EAR 映射／門檻不適合 test1 的人物與拍攝條件，而不是 PTS、3-of-5、
  face detection 或 pitch 判斷失敗。
- Pilot v1 三支影片的 `eye_closed` Ground Truth support 為 0，沒有真正閉眼樣本可估計 Recall，
  因此現在不能根據正常幀單方面把門檻調低；那會有漏掉真正閉眼的風險。
- 在取得校正影片以前停止修改 FrameClassifier。

### 下一個最小實驗：閉眼校正影片

使用同一支 iPhone 16、相近距離與光線，固定拍攝一支約 30–45 秒影片，依序包含：

1. 0–8 秒：正常睜眼看前方，標為 `normal`。
2. 8–13 秒：自然眨眼數次，Ground Truth 仍標為 `normal`。
3. 13–18 秒：持續閉眼約 5 秒，標為 `eye_closed`。
4. 18–26 秒：低頭但眼睛保持睜開，標為 `posture_down` 或依實際研究定義標記。
5. 26 秒到結束：回正並正常睜眼，標為 `normal`。

這支影片只用於選擇閉眼門檻；調整完成後，必須另外錄製至少一支未參與調參的驗證影片，
再報告新的 Precision／Recall／F1，不能直接用校正影片宣稱改善。

---

## 新實驗模板

複製本節並附加到文件尾端；不要覆寫舊實驗。

### 實驗名稱：`<名稱>`

- 日期：`YYYY-MM-DD`
- 目的／假設：
- Git branch／commit：
- FrameClassifier／策略版本：
- 投票設定：
- Ground Truth 標記者與規則：

#### 影片來源

| 影片 | 來源／拍攝方式 | 拍攝裝置 | 內容 | Run ID | 幀數 | PTS 範圍 |
| --- | --- | --- | --- | --- | ---: | ---: |
|  |  |  |  |  |  |  |

#### 結果

| 影片 | 策略 | Frame accuracy | Precision／Recall／F1 | 誤報 | 漏失 | 狀態切換 | 平均延遲 |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: |
|  |  |  |  |  |  |  |  |

#### 觀察與決策

- 觀察：
- 已知限制：
- 是否支持假設：
- 下一步／停止條件：
