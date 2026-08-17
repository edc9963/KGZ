# 快記帳 LINE Rich Menu：雙入口版

## 上傳圖片

- 檔案：`rich-menu-two-action.png`
- 畫布：`2500 × 1686 px`
- 格式：PNG / RGB
- 配置：左側 2/3 主操作、右側 1/3 次操作
- 座標原點：圖片左上角 `(0, 0)`

## 視覺規格

| 用途 | 色彩 |
|---|---|
| 品牌／主操作 | `#2387B8` |
| 新增輔色 | `#2A9D8F` |
| 主文字 | `#1F2D33` |
| 次文字 | `#56666D` |
| 淡藍表面 | `#F3F8FA` |
| 分隔線 | `#DCE3E6` |
| 反白文字 | `#FFFFFF` |

- 字體：Noto Sans CJK TC；Bold 用於入口名稱，Regular 用於輔助說明。
- 安全區：主區左右至少 `152 px`、副區左右至少 `92 px`；重要文字不跨越 `x = 1667` 分隔線。
- 視覺分區與實際 action bounds 完全一致，兩區無重疊、無缺口。

## 點擊區域

| 入口 | x | y | width | height | 動作 |
|---|---:|---:|---:|---:|---|
| 新增紀錄 | 0 | 0 | 1667 | 1686 | Postback：`expense:start` |
| 財務總覽 | 1667 | 0 | 833 | 1686 | URI：登入後前往 `/dashboard` |

## LINE Messaging API `areas` JSON

部署前請將 `YOUR_APP_URL` 替換為正式 HTTPS 網域。

```json
{
  "size": {
    "width": 2500,
    "height": 1686
  },
  "selected": true,
  "name": "快記帳｜快速入口",
  "chatBarText": "開啟快記帳",
  "areas": [
    {
      "bounds": {
        "x": 0,
        "y": 0,
        "width": 1667,
        "height": 1686
      },
      "action": {
        "type": "postback",
        "label": "新增紀錄",
        "data": "expense:start",
        "displayText": "新增紀錄"
      }
    },
    {
      "bounds": {
        "x": 1667,
        "y": 0,
        "width": 833,
        "height": 1686
      },
      "action": {
        "type": "uri",
        "label": "財務總覽",
        "uri": "https://YOUR_APP_URL/login?source=line_oa&next=%2Fdashboard"
      }
    }
  ]
}
```

## 上線檢查

1. 替換 `YOUR_APP_URL`，確認 URI 使用 HTTPS。
2. 確認 webhook 會處理 postback data `expense:start`。
3. 建立 Rich Menu、上傳本 PNG，再設為預設 Rich Menu。
4. 以 LINE iOS 與 Android 實機各測試一次登入導向與 postback 回應。
