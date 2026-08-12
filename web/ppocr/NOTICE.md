# PP-OCRv5 browser assets

These files are pinned application assets. They are served only from the
application's own origin and cached by `web/kgz_ocr.js`.

- `PP-OCRv5_mobile_det.onnx`
  - Source: `BMekiker/PP-OCRv5_ONNX`
  - SHA-256: `d7fe3ea74652890722c0f4d02458b7261d9f5ae6c92904d05707c9eb155c7924`
- `PP-OCRv5_server_rec.onnx`
  - Source: `bluecopa/paddleocr-v5-onnx`
  - Pinned source revision: `a6159f8`
  - SHA-256: `13d0dda27d63dc0f4938af48df2c55b33f3c989a0bd5eacb8410e30f1735f644`
- `ppocrv5_dict.txt`
  - Source: `BMekiker/PP-OCRv5_ONNX`
  - SHA-256: `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b`
- `ort.webgpu.min.js` and `ort-wasm-*`
  - ONNX Runtime Web 1.22.0

PaddleOCR is distributed under the Apache License 2.0. ONNX Runtime is
distributed under the MIT License. The converted model assets retain the
upstream PaddleOCR model terms.
