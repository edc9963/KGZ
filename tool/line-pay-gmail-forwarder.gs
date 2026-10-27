/**
 * 快記帳：銀行通知信（LINE Pay 刷卡、彰銀 TWPAY／金融卡扣帳）→ card-email-ingest
 *
 * LINE Pay 綁信用卡付款時，發卡銀行會寄刷卡通知信；彰化銀行數位存款帳戶的
 * TWPAY 掃碼與金融卡消費會寄「扣帳通知」。這支 Google Apps Script 每 10 分鐘
 * 掃一次 Gmail，把這些通知送到 Supabase 的 card-email-ingest；伺服器解析後
 * 存進待確認收件匣，再由 LINE 推播確認。轉帳、提款等非消費扣帳會被略過。
 *
 * 設定方式：
 *   1. https://script.google.com 新增專案，貼上這個檔案。
 *   2. 專案設定 →「指令碼屬性」新增：
 *        KGZ_URL    LINE 官方帳號「捷徑設定」→「產生金鑰」訊息中的銀行通知信網址
 *        KGZ_TOKEN  同一則訊息後面那把 kgz_ 開頭的金鑰
 *        KGZ_QUERY  （選填）自訂 Gmail 搜尋條件，例如加上 from:銀行網域
 *   3. 執行一次 runOnce 授權並確認「執行記錄」沒有錯誤。
 *   4. 執行 install 建立每 10 分鐘的觸發條件。
 *
 * 解析在伺服器端進行，銀行改信件格式時不需要改這支腳本。信件內容只送到
 * KGZ_URL，不會寫進記錄。
 */

// Gmail binds OR tighter than the implied AND, so every group is explicit.
var DEFAULT_QUERY =
  'newer_than:2d ((("LINE Pay" OR LINEPAY OR 連加) (消費 OR 刷卡 OR 交易)) OR ' +
  '(from:bill.chb.com.tw 扣帳通知))';
var MAX_BODY_CHARS = 20000;
// Re-send a little before the last checkpoint: the server ignores repeats
// (by Message-ID), and Gmail can index a message after a later one.
var OVERLAP_MS = 30 * 60 * 1000;

function runOnce() {
  var properties = PropertiesService.getScriptProperties();
  var url = properties.getProperty('KGZ_URL');
  var token = properties.getProperty('KGZ_TOKEN');
  if (!url || !token) {
    throw new Error('請先在指令碼屬性設定 KGZ_URL 與 KGZ_TOKEN');
  }
  var query = properties.getProperty('KGZ_QUERY') || DEFAULT_QUERY;
  var since = Number(properties.getProperty('KGZ_SINCE') || 0);

  var messages = [];
  GmailApp.search(query, 0, 50).forEach(function (thread) {
    thread.getMessages().forEach(function (message) {
      if (message.getDate().getTime() > since - OVERLAP_MS) messages.push(message);
    });
  });
  messages.sort(function (a, b) {
    return a.getDate().getTime() - b.getDate().getTime();
  });

  var checkpoint = since;
  for (var i = 0; i < messages.length; i++) {
    var message = messages[i];
    var status = send(url, token, message);
    if (status === 'retry') break; // keep the checkpoint; try again next run
    checkpoint = Math.max(checkpoint, message.getDate().getTime());
  }
  properties.setProperty('KGZ_SINCE', String(checkpoint));
}

function send(url, token, message) {
  var body = message.getPlainBody() || message.getBody();
  var response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-capture-token': token },
    payload: JSON.stringify({
      messageId: message.getHeader('Message-ID') || message.getId(),
      from: message.getFrom(),
      subject: message.getSubject(),
      body: body.slice(0, MAX_BODY_CHARS),
      receivedAt: message.getDate().toISOString(),
    }),
    muteHttpExceptions: true,
  });
  var code = response.getResponseCode();
  var result = {};
  try {
    result = JSON.parse(response.getContentText());
  } catch (error) {
    // Non-JSON error page; the status code says enough.
  }
  console.log(code + ' ' + (result.status || result.message || '') +
    (result.reason ? ' (' + result.reason + ')' : ''));
  if (code === 401) {
    throw new Error('金鑰無效：請到 LINE「捷徑設定」重新產生，並更新 KGZ_TOKEN');
  }
  if (code === 429 || code >= 500) return 'retry';
  return 'done';
}

function install() {
  ScriptApp.getProjectTriggers().forEach(function (trigger) {
    if (trigger.getHandlerFunction() === 'runOnce') ScriptApp.deleteTrigger(trigger);
  });
  ScriptApp.newTrigger('runOnce').timeBased().everyMinutes(10).create();
}
