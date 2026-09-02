# LINE Webhook

此 Function 必須使用 `--no-verify-jwt` 部署，因為來源是 LINE；安全邊界是
未修改 raw body 的 HMAC-SHA256 `x-line-signature`。必要 Secrets：

- `LINE_CHANNEL_SECRET`
- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_BOT_USER_ID`（選用；只用來偵測 webhook destination 設定錯誤）
- `APP_PUBLIC_URL`（第一階段可省略）

Supabase 自動提供 `SUPABASE_URL` 與 `SUPABASE_SERVICE_ROLE_KEY`。Function
不記錄原始訊息或圖片，財務功能只接受 `source.type=user` 的一對一事件。
請填 Messaging API 頁面顯示、以 `U` 開頭的 Bot User ID，不是官方帳號的
`@Basic ID`。若未設定或誤填，簽章正確的事件仍會處理，並在 Function Logs
留下不含使用者 ID 的 `line_destination_mismatch` 警告。
