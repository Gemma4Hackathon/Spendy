# Spendy – Demo Script

This is the primary walkthrough for a live hackathon demo (≈ 3–5 min).

---

## Demo Scenario: "都市上班族的隱形風險"

**角色設定**：Alex Chen，28 歲男性，科技業工程師，外食為主，常外送 + 喝手搖飲 + 夜生活

---

## Step-by-Step Flow

### Step 1 – 個人資料頁 (30 sec)
- 打開 app，進入「個人資料」tab
- 點「**載入 Demo 情境**」按鈕
- 頁面顯示 Alex Chen 的資料：175cm / 79.2kg / BMI 25.8（過重）
- 健康目標：控制血糖、改善睡眠、減重 5 公斤
- **說明重點**：這些基本資料會成為 AI 分析的背景脈絡

---

### Step 2 – 消費記錄頁 (45 sec)
- 切換到「消費記錄」tab
- 顯示本月消費：NT$3,240，共 20 筆
- 類別分佈條：外送餐飲佔最高，含糖飲料第二
- **說明重點**：可以用自然語言輸入，也可手動分類；這是原始消費資料

---

### Step 3 – 財務助手頁 (45 sec)
- 切換到「財務助手」tab
- AI 開始打字輸出分析（typewriter 動畫）
- 標記高風險消費：含糖飲料 NT$645、深夜外送 NT$1,450
- **說明重點**：這頁是財務端的 copilot，先把消費結構說清楚；但還沒有跨到健康面

---

### Step 4 – 健檢掃描頁 (30 sec)
- 切換到「健檢掃描」tab
- 點「**使用 Demo 健檢數據**」（模擬掃描動畫 2.5 秒）
- OCR 處理動畫結束後自動跳轉到健檢結果頁
- **說明重點**：實際情境可拍照或從相簿選取健檢報告，Gemma 4 multimodal 自動提取

---

### Step 5 – 健檢結果頁 (45 sec)
- 顯示解析後的 8 個健康指標
- 用顏色標示：血壓、LDL、三酸甘油脂（紅/警告）；血糖、HbA1c、BMI（黃/邊緣）
- 動畫進度條逐一顯示各指標相對於正常值的位置
- 底部大按鈕：「查看 Health × Finance 分析報告」
- **說明重點**：先把健康端講清楚，讓評審知道「這個人有哪些指標需要注意」

---

### Step 6 – 分析報告頁（亮點！）(90 sec)
- 點 CTA 按鈕進入「分析報告」tab
- 顯示**風險指數儀表板**：68/100，中高度風險，動畫填充
- 顯示 3 張**跨領域關聯卡片**：

  **卡片 1：🧋 高糖飲品 → 血糖偏高**
  - 消費：NT$645 / 月，每天 1.2 杯全糖手搖飲
  - 影響：血糖 112 mg/dL（超標），HbA1c 6.1%（前期糖尿病）
  - 行動：改成無糖 → 3 個月後血糖可恢復正常

  **卡片 2：🌙 深夜外送 → 膽固醇 + 代謝**
  - 消費：外送佔 43% 總支出，平均 22:30 點餐
  - 影響：LDL 145、三酸甘油脂 198（均偏高）
  - 行動：晚餐提前至 19:00 → 1 個月可降低三酸甘油脂 15%

  **卡片 3：☕ 咖啡因依賴 → 血壓 + 睡眠**
  - 消費：每週咖啡 NT$825，集中在下午
  - 影響：血壓 138/89（偏高），疲勞惡性循環
  - 行動：14:00 後停止咖啡因 → 2 週改善睡眠

- **說明重點**：這就是 Spendy 的核心價值 — 把「你的錢花哪裡」和「你身體出了什麼問題」連結起來

---

## Key Talking Points

1. **跨領域 Pattern Intelligence**：不只看財務，不只看健康，兩者合看才有意義
2. **Privacy-first**：Gemma 4 on-device（LiteRT + Cactus），健康資料不離開手機
3. **Educational, not diagnostic**：不取代醫生，而是幫助使用者建立行為意識
4. **Demo-ready**：一顆按鈕載入完整 Demo，評審 5 分鐘內可完整體驗

---

## Hackathon Tracks Alignment

| Track | Alignment |
|---|---|
| Health & Sciences | 健檢資料 × 行為模式分析 |
| Cactus | on-device routing，local-first 設計 |
| LiteRT | Gemma 4 on-device inference on iPhone |
| Unsloth | Fine-tuned on medical knowledge QA |
