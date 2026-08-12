# LINE Rich Menu

`assets/rich-menu.png` 必須維持 2500×1686 且小於 1 MB。建立 LINE
Messaging API Channel 後，在本機設定 Channel Access Token：

```powershell
$env:LINE_CHANNEL_ACCESS_TOKEN = '...'
node tool/line/setup-rich-menu.mjs
```

如果已部署 Firebase Hosting，可同時設定 `APP_PUBLIC_URL`；右下角會導向
`/login?source=line_oa&next=%2Fdashboard`，讓 LINE 內建瀏覽器自動啟動
LINE Login。未設定時會顯示尚未開放，不會導向不存在的網址。

可在不呼叫 LINE API 的情況下驗證圖片與登入網址：

```powershell
$env:APP_PUBLIC_URL = 'https://你的網域'
node tool/line/setup-rich-menu.mjs --validate-only
```
