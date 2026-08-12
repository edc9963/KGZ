# 快記帳

繁體中文的個人記帳與資產管理 Flutter Web 應用。登入後的財務資料會
儲存在 Supabase Postgres，並以 RLS 隔離不同使用者；瀏覽器只保留最後一次
成功同步的唯讀快取。LINE 官方帳號可查詢總覽、快速記錄支出及處理
待收款。Uber Eats 截圖目前仍使用瀏覽器內的 Tesseract.js OCR；官方帳號
收到圖片時不會下載或保存。

主導覽整合為財務總覽、日常帳務、資產管理、代訂收款與設定五個工作區；
「日常帳務」可維護一般收入、支出、信用卡與每月固定支出，設定頁可自訂
收入／支出分類的名稱、圖示、色彩、順序與啟用狀態。電信帳單繳費會把
代收消費併入每月月租，於繳費日由指定銀行帳戶一次扣款。這些報表用於個人財務管理，
不是 IFRS／GAAP 法定財報。

## 執行

請先安裝包含 Dart 3.8 以上的 Flutter stable，並執行
`flutter config --enable-web`。

```bash
flutter pub get
flutter run -d chrome
```

## Supabase、LINE Login 與截圖辨識

1. 建立 Supabase 專案並套用 `supabase/migrations`：

```bash
npx supabase link --project-ref <project-ref>
npx supabase db push
```

schema v7 以統一交易與帳戶影響保存資產、負債及應收款，並保留 v6
固定支出、產生紀錄與電信帳單付款資料。遷移會啟用
`pg_cron`，並在每日台北時間 00:15 補入到期支出。請先完成
`npx supabase db push`，再發布新版 Web App；使用者完成 v7 升級後，新 RPC
會拒絕舊版寫入，避免舊瀏覽器覆蓋統一帳務與分類資料。

財務資料透過 `load_finance_data`、`save_finance_data` 與
`clear_finance_data` RPC 原子讀寫，並用 revision 防止其他裝置的舊版本
覆蓋新資料。第一次登入若偵測到本機資料，會要求選擇上傳、合併或使用
雲端版本。

2. 在 Supabase Auth 建立識別碼為 `custom:line` 的 Custom OIDC provider：
   使用 Manual OAuth2，Authorization URL 為
   `https://access.line.me/oauth2/v2.1/authorize`、Token URL 為
   `https://api.line.me/oauth2/v2.1/token`、UserInfo URL 指向部署後的
   `https://<project-ref>.supabase.co/functions/v1/line-userinfo`。Scope 使用
   `openid, profile`，開啟 PKCE 與 email optional；將 Supabase 顯示的
   callback URL 登記到 LINE Login Channel。`line-userinfo` 只驗證 LINE
   access token 並補上供 Supabase 識別的內部假名 Email，不會取得真實
   LINE Email 或保存個人資料。Supabase 的 Redirect URL allowlist 也必須
   包含正式網站來源（例如 `https://你的網域/**`），才能安全返回原本頁面。
3. 部署 LINE UserInfo 相容層：

```bash
supabase functions deploy line-userinfo --no-verify-jwt
```

截圖辨識不需要 `OPENAI_API_KEY`。固定版本的 Tesseract.js、WASM、
繁體中文與英文模型都鎖定在 `web` 並隨網站部署；截圖只在瀏覽器內
分區辨識，不會上傳到 OCR API 或外部 CDN。

### LINE 官方帳號

1. 在 LINE Official Account Manager 建立官方帳號，啟用 Messaging API 時
   必須選擇現有 LINE Login Channel 所屬的同一個 Provider。
2. 在 Supabase 設定並部署：

```powershell
npx supabase secrets set `
  LINE_CHANNEL_SECRET=... `
  LINE_CHANNEL_ACCESS_TOKEN=... `
  LINE_BOT_USER_ID=... ` # 選用；須為 U 開頭的 Bot User ID，不是 @Basic ID
  APP_PUBLIC_URL=https://你的網域 `
  OCR_ENABLED=false
npx supabase db push
npx supabase functions deploy line-webhook --no-verify-jwt
```

3. LINE Developers Console 的 Webhook URL 設為：

```text
https://lxmxtbcrflmflpffaswc.supabase.co/functions/v1/line-webhook
```

開啟 `Use webhook` 與 webhook redelivery，並關閉會和 Bot 重複回覆的
自動回應。Webhook 只接受一對一聊天室；第一次使用會要求明確確認帳號
連結。

4. 設定預設 Rich Menu：

```powershell
$env:LINE_CHANNEL_ACCESS_TOKEN = '...'
$env:APP_PUBLIC_URL = 'https://你的網域'
node tool/line/setup-rich-menu.mjs
```

「開啟快記帳」會導向
`/login?source=line_oa&next=%2Fdashboard`。這個來源標記只會啟動一次既有的
LINE OAuth，不會作為身分證明；取消或失敗後必須由使用者按登入按鈕重試。
登入完成也不會自動授權 Bot，使用者仍須回到官方帳號按「確認連結」。

Bot 使用 service-role 專用 RPC 寫入，每次支出或收款都會在同一交易內
遞增雲端 revision，因此開著舊資料的網頁會收到 conflict，而不會蓋掉
LINE 新增的資料。Secret 不得放入 Flutter 或提交到專案。

### 第二階段 OCR 與 Firebase

`ocr-worker` 已包含 Cloud Run Dockerfile、HMAC 驗證、Sharp 前處理、
Tesseract.js 與 Uber Eats 草稿解析器；`firebase.json` 已設定 Flutter SPA
rewrite。兩者目前不部署，`OCR_ENABLED` 必須維持 `false`。建立 GCP 專案
後再複製 `.firebaserc.example` 為 `.firebaserc`、設定公開網址及 Worker
Secret，並一起啟用圖片 session、短效 review token 與清除排程。

### PWA

網站 manifest、Apple Touch Icon、favicon 與 maskable icon 使用深炭灰、
青藍及暖黃色的「借貸扣合勾號」。Chrome／Safari 可將網站加入主畫面；
從官方帳號開啟時則留在 LINE 內建瀏覽器，因此不保證安裝提示或完整的
Service Worker 行為。發布前以 Chrome DevTools 的 Application 面板確認
manifest、icon、scope 與 service worker，並實測安裝後的獨立啟動。

4. 啟動 Flutter Web 時傳入公開設定（OpenAI key 不可放在前端）：

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://你的專案.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

截圖支援 PNG、JPEG、WebP，一次最多 6 張、單張 6 MB、總計 20 MB。
所有分攤與最終收款皆以整數新台幣計算；外送費、服務費預設不包含本人。
折扣改由每位參與者勾選，預設全不勾；勾選者平均分配，也可固定個別金額，
其餘折扣會由尚未固定的勾選者自動補平。

## 驗證

```bash
flutter analyze
flutter test
flutter build web --release
npx supabase test db
```

Supabase SQL 測試需要已啟動的 Docker Desktop 或 Podman 本機 stack。

登入後可在「設定」產生測試資料、匯出各類 CSV，或只清除標記為測試資料的內容。

`/collect/{token}` 使用高熵 token 透過限權匿名 RPC 讀取單一付款請求，
付款人可在不同裝置查看金額並按「我已付款」。部署新版 Web App 前必須先
套用 `202608120001_public_collection.sql`；RPC 不會回傳收款人的使用者 ID、
信用卡或其他財務資料，匿名更新也只允許把 `unpaid` 改成 `pending`。

## 原型限制

- 離線時可查看最後成功同步的快取，但不能新增、修改或刪除資料。
- QR 圖片以文字形式模擬設定；尚未串接銀行、LINE Pay 或任何付款 API。
- LINE 官方帳號圖片 OCR、Cloud Run 與 Firebase Hosting 預設停用。
