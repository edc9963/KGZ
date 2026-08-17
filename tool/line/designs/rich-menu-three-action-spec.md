# LINE Rich Menu：三入口品牌版

## 圖片

- 檔案：`rich-menu-two-action.png`
- 格式：PNG
- 尺寸：2500 × 1686 px
- 版型：左側主操作，右側上下兩個次操作

## 配色

採用沉穩海軍藍作為主操作底色，搭配霧藍與鼠尾草綠區分兩個查閱入口，再以珊瑚橘集中強調可執行操作。整體維持金融產品所需的可信賴感，同時降低原品牌三色大面積並置造成的視覺刺激。

| 用途 | 色碼 |
| --- | --- |
| 深海軍藍／主文字 | `#18324B` |
| 霧藍／財務總覽 | `#DDEFF2` |
| 鼠尾草綠／會計帳 | `#BFD9CF` |
| 珊瑚橘／操作強調 | `#F27A64` |
| 柔白／圖示與分隔 | `#F7F6F2` |

## 點擊區域

畫布原點位於左上角。三區完整覆蓋畫布，沒有重疊或空隙。

| 功能 | x | y | width | height | 動作 |
| --- | ---: | ---: | ---: | ---: | --- |
| 新增紀錄 | 0 | 0 | 1667 | 1686 | Postback |
| 財務總覽 | 1667 | 0 | 833 | 843 | URI |
| 開啟會計帳 | 1667 | 843 | 833 | 843 | URI |

## LINE Messaging API action JSON

請將 `YOUR_APP_DOMAIN` 替換為正式網域。財務總覽與會計帳皆先經登入頁，登入完成後分別導向 `/dashboard` 與 `/accounts`。

```json
{
  "size": {
    "width": 2500,
    "height": 1686
  },
  "selected": true,
  "name": "快記帳｜主要功能",
  "chatBarText": "開啟快記帳",
  "areas": [
    {
      "bounds": { "x": 0, "y": 0, "width": 1667, "height": 1686 },
      "action": {
        "type": "postback",
        "label": "新增紀錄",
        "data": "expense:start",
        "displayText": "新增紀錄"
      }
    },
    {
      "bounds": { "x": 1667, "y": 0, "width": 833, "height": 843 },
      "action": {
        "type": "uri",
        "label": "財務總覽",
        "uri": "https://YOUR_APP_DOMAIN/login?redirect=/dashboard"
      }
    },
    {
      "bounds": { "x": 1667, "y": 843, "width": 833, "height": 843 },
      "action": {
        "type": "uri",
        "label": "開啟會計帳",
        "uri": "https://YOUR_APP_DOMAIN/login?redirect=/accounts"
      }
    }
  ]
}
```

## 上傳前檢查

1. 替換兩個 URI 中的 `YOUR_APP_DOMAIN`。
2. 確認 LINE webhook 已處理 `expense:start` postback。
3. 確認登入流程允許並正確處理 `/dashboard`、`/accounts` redirect。
4. 圖片上傳時使用 `image/png`。
