# Cloud Run OCR Worker（第二階段）

目前只準備程式，不部署。Worker 以 Tesseract.js（`chi_tra`＋`eng`）辨識，
Sharp 負責旋轉、灰階與對比處理。請求使用 `OCR_WORKER_HMAC_SECRET` 驗證，
Worker 不持有 Supabase service-role key。

建議部署於 `asia-east1`，規格已寫入 `cloud-run.yaml`：1 vCPU、2 GiB、
concurrency 1、min 0、max 2、timeout 300 秒。

