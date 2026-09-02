(function () {
  "use strict";

  const ASSET_ROOT = new URL("assets/web/ppocr/", document.baseURI).href;
  const TESSERACT_ROOT = new URL(
    "assets/web/tesseract/",
    document.baseURI
  ).href;
  const CACHE_NAME = "kgz-ppocr-v5-adaptive-v1";
  const ENGINE_VERSION = "ppocr-v5-mobile-det+adaptive-rec@v1";
  const MODEL_ASSETS = {
    detector: `${ASSET_ROOT}PP-OCRv5_mobile_det.onnx`,
    serverRecognizer: `${ASSET_ROOT}PP-OCRv5_server_rec.onnx`,
    mobileRecognizer: `${ASSET_ROOT}PP-OCRv5_mobile_rec.onnx`,
    dictionary: `${ASSET_ROOT}ppocrv5_dict.txt`,
  };
  const MODEL_BYTES = {
    detector: 4_748_769,
    serverRecognizer: 84_505_505,
    mobileRecognizer: 16_534_782,
    dictionary: 74_012,
  };

  let runtimePromise;
  let tesseractWorkerPromise;

  function progress(stage, value, message, current, total, engine) {
    if (typeof window.kgzOcrProgress !== "function") return;
    window.kgzOcrProgress(
      JSON.stringify({
        stage,
        progress: Math.max(0, Math.min(1, Number(value) || 0)),
        message,
        current: current || 0,
        total: total || 0,
        engine: engine || "",
      })
    );
  }

  function loadImage(source) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error("無法讀取截圖"));
      image.src = source;
    });
  }

  function prefersMobileRecognizer() {
    const agent = navigator.userAgent || "";
    const iPadDesktopMode =
      /Macintosh/.test(agent) && Number(navigator.maxTouchPoints || 0) > 1;
    const mobileDevice =
      /iPad|iPhone|iPod|Android/.test(agent) || iPadDesktopMode;
    const memory = Number(navigator.deviceMemory || 0);
    return mobileDevice || (memory > 0 && memory <= 4);
  }

  function needsIphoneLowMemoryMode() {
    const agent = navigator.userAgent || "";
    return (
      /iPad|iPhone|iPod/.test(agent) ||
      (/Macintosh/.test(agent) && Number(navigator.maxTouchPoints || 0) > 1)
    );
  }

  async function fetchCached(url, onBytes) {
    const cache =
      typeof caches === "undefined" ? null : await caches.open(CACHE_NAME);
    const cached = cache ? await cache.match(url) : null;
    if (cached) {
      const bytes = new Uint8Array(await cached.arrayBuffer());
      onBytes(bytes.byteLength, bytes.byteLength);
      return bytes;
    }

    const response = await fetch(url, { cache: "force-cache" });
    if (!response.ok) {
      throw new Error(`模型下載失敗 (${response.status})`);
    }
    const expected = Number(response.headers.get("content-length")) || 0;
    if (!response.body) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      onBytes(bytes.byteLength, bytes.byteLength);
      if (cache) {
        await cache.put(
          url,
          new Response(bytes, {
            headers: { "content-type": "application/octet-stream" },
          })
        );
      }
      return bytes;
    }

    const reader = response.body.getReader();
    const chunks = [];
    let received = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      received += value.byteLength;
      onBytes(received, expected);
    }
    const bytes = new Uint8Array(received);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    if (cache) {
      await cache.put(
        url,
        new Response(bytes, {
          headers: { "content-type": "application/octet-stream" },
        })
      );
    }
    return bytes;
  }

  async function deleteOldModelCaches() {
    if (typeof caches === "undefined") return;
    const names = await caches.keys();
    await Promise.all(
      names
        .filter(
          (name) => name.startsWith("kgz-ppocr-") && name !== CACHE_NAME
        )
        .map((name) => caches.delete(name))
    );
  }

  async function loadRuntime() {
    if (runtimePromise) return runtimePromise;
    runtimePromise = (async () => {
      if (!window.ort) throw new Error("ONNX Runtime Web 尚未載入");
      progress("runtime", 0.02, "正在載入本機 OCR 執行環境");
      ort.env.wasm.wasmPaths = ASSET_ROOT;
      ort.env.wasm.numThreads = 1;
      await deleteOldModelCaches();

      const mobileRecognizer = prefersMobileRecognizer();
      const recognizerAsset = mobileRecognizer
        ? MODEL_ASSETS.mobileRecognizer
        : MODEL_ASSETS.serverRecognizer;
      const recognizerBytesExpected = mobileRecognizer
        ? MODEL_BYTES.mobileRecognizer
        : MODEL_BYTES.serverRecognizer;

      const loaded = { detector: 0, recognizer: 0, dictionary: 0 };
      const totals = {
        detector: MODEL_BYTES.detector,
        recognizer: recognizerBytesExpected,
        dictionary: MODEL_BYTES.dictionary,
      };
      const updateDownload = (key, received, total) => {
        loaded[key] = received;
        if (total) totals[key] = total;
        const done = Object.values(loaded).reduce((sum, value) => sum + value, 0);
        const all = Object.values(totals).reduce((sum, value) => sum + value, 0);
        progress(
          "download",
          done / Math.max(1, all),
          `正在準備高精度 OCR 模型 ${Math.round((done / Math.max(1, all)) * 100)}%`,
          done,
          all
        );
      };

      const [detectorBytes, recognizerBytes, dictionaryBytes] =
        await Promise.all([
          fetchCached(MODEL_ASSETS.detector, (a, b) =>
            updateDownload("detector", a, b)
          ),
          fetchCached(recognizerAsset, (a, b) =>
            updateDownload("recognizer", a, b)
          ),
          fetchCached(MODEL_ASSETS.dictionary, (a, b) =>
            updateDownload("dictionary", a, b)
          ),
        ]);
      const dictionary = new TextDecoder("utf-8")
        .decode(dictionaryBytes)
        .replace(/\r/g, "")
        .split("\n")
        .filter((value) => value.length > 0);

      let gpuAvailable = false;
      if (navigator.gpu) {
        try {
          gpuAvailable = !!(await navigator.gpu.requestAdapter());
        } catch (_) {
          gpuAvailable = false;
        }
      }
      // Safari's WebGPU process has a much tighter memory budget than desktop
      // browsers. The mobile recognizer is fast enough on single-threaded WASM
      // and avoids a second GPU copy of the model weights.
      const preferred =
        !mobileRecognizer && gpuAvailable ? ["webgpu"] : ["wasm"];
      let detector;
      let recognizer;
      let engine = preferred[0];
      progress("runtime", 0.7, "正在建立本機 OCR 模型");
      try {
        detector = await ort.InferenceSession.create(detectorBytes, {
          executionProviders: preferred,
          graphOptimizationLevel: "all",
        });
        recognizer = await ort.InferenceSession.create(recognizerBytes, {
          executionProviders: preferred,
          graphOptimizationLevel: "all",
        });
      } catch (error) {
        if (preferred[0] !== "webgpu") throw error;
        progress("runtime", 0.78, "WebGPU 無法載入，正在改用 WASM CPU");
        engine = "wasm";
        detector = await ort.InferenceSession.create(detectorBytes, {
          executionProviders: ["wasm"],
          graphOptimizationLevel: "all",
        });
        recognizer = await ort.InferenceSession.create(recognizerBytes, {
          executionProviders: ["wasm"],
          graphOptimizationLevel: "all",
        });
      }
      progress(
        "runtime",
        1,
        mobileRecognizer
          ? "行動版 PP-OCR 已使用低記憶體模式"
          : engine === "webgpu"
          ? "高精度 OCR 已使用 WebGPU"
          : "高精度 OCR 已使用 WASM，辨識速度可能較慢",
        0,
        0,
        mobileRecognizer ? "PP-OCRv5 mobile / WASM" : engine
      );
      return {
        detector,
        recognizer,
        dictionary,
        engine,
        recognizerProfile: mobileRecognizer ? "mobile" : "server",
        engineLabel: mobileRecognizer ? "PP-OCRv5 mobile / WASM" : engine,
      };
    })();
    try {
      return await runtimePromise;
    } catch (error) {
      runtimePromise = null;
      throw error;
    }
  }

  function imageCanvas(image) {
    const canvas = document.createElement("canvas");
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.drawImage(image, 0, 0);
    return canvas;
  }

  function resizeCanvas(source, width, height, fillWhite) {
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (fillWhite) {
      context.fillStyle = "#fff";
      context.fillRect(0, 0, width, height);
    }
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(source, 0, 0, width, height);
    return canvas;
  }

  function cropCanvas(source, left, top, width, height) {
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(width));
    canvas.height = Math.max(1, Math.round(height));
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.fillStyle = "#fff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(
      source,
      Math.round(left),
      Math.round(top),
      Math.round(width),
      Math.round(height),
      0,
      0,
      canvas.width,
      canvas.height
    );
    return canvas;
  }

  function canvasTensor(canvas, mean, std) {
    const { width, height } = canvas;
    const pixels = canvas
      .getContext("2d", { willReadFrequently: true })
      .getImageData(0, 0, width, height).data;
    const plane = width * height;
    const values = new Float32Array(plane * 3);
    for (let index = 0; index < plane; index += 1) {
      values[index] = (pixels[index * 4] / 255 - mean[0]) / std[0];
      values[plane + index] =
        (pixels[index * 4 + 1] / 255 - mean[1]) / std[1];
      values[plane * 2 + index] =
        (pixels[index * 4 + 2] / 255 - mean[2]) / std[2];
    }
    return new ort.Tensor("float32", values, [1, 3, height, width]);
  }

  function connectedTextBoxes(values, width, height) {
    const mask = new Uint8Array(width * height);
    let minimum = Infinity;
    let maximum = -Infinity;
    for (let index = 0; index < values.length; index += 1) {
      minimum = Math.min(minimum, values[index]);
      maximum = Math.max(maximum, values[index]);
    }
    // Paddle's sigmoid output can overshoot zero/one by float epsilon.
    // Treat only material excursions as logits; otherwise a second sigmoid
    // turns the background into ~0.5 and connects the whole page.
    const logits = minimum < -0.001 || maximum > 1.001;
    for (let index = 0; index < mask.length; index += 1) {
      const probability = logits ? 1 / (1 + Math.exp(-values[index])) : values[index];
      if (probability >= 0.28) mask[index] = 1;
    }

    const queue = new Int32Array(mask.length);
    const boxes = [];
    for (let start = 0; start < mask.length; start += 1) {
      if (!mask[start]) continue;
      let head = 0;
      let tail = 0;
      queue[tail++] = start;
      mask[start] = 0;
      let left = width;
      let right = 0;
      let top = height;
      let bottom = 0;
      let score = 0;
      let count = 0;
      while (head < tail) {
        const current = queue[head++];
        const y = Math.floor(current / width);
        const x = current - y * width;
        left = Math.min(left, x);
        right = Math.max(right, x);
        top = Math.min(top, y);
        bottom = Math.max(bottom, y);
        const raw = values[current];
        score += logits ? 1 / (1 + Math.exp(-raw)) : raw;
        count += 1;
        for (let dy = -1; dy <= 1; dy += 1) {
          const ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (let dx = -1; dx <= 1; dx += 1) {
            const nx = x + dx;
            if (nx < 0 || nx >= width || (dx === 0 && dy === 0)) continue;
            const next = ny * width + nx;
            if (mask[next]) {
              mask[next] = 0;
              queue[tail++] = next;
            }
          }
        }
      }
      const boxWidth = right - left + 1;
      const boxHeight = bottom - top + 1;
      if (
        count >= 8 &&
        boxWidth >= 5 &&
        boxHeight >= 3 &&
        score / count >= 0.36
      ) {
        const horizontalPad = Math.max(2, boxHeight * 0.45);
        const verticalPad = Math.max(2, boxHeight * 0.18);
        boxes.push({
          left: Math.max(0, left - horizontalPad),
          top: Math.max(0, top - verticalPad),
          right: Math.min(width, right + 1 + horizontalPad),
          bottom: Math.min(height, bottom + 1 + verticalPad),
          detectionConfidence: score / count,
        });
      }
    }
    return mergeSameLineBoxes(boxes);
  }

  function mergeSameLineBoxes(boxes) {
    boxes.sort((a, b) => a.top - b.top || a.left - b.left);
    const result = [];
    for (const box of boxes) {
      const height = box.bottom - box.top;
      let target = null;
      for (let index = result.length - 1; index >= 0; index -= 1) {
        const candidate = result[index];
        if (box.top - candidate.bottom > height) break;
        const overlap =
          Math.min(box.bottom, candidate.bottom) -
          Math.max(box.top, candidate.top);
        const minHeight = Math.min(
          height,
          candidate.bottom - candidate.top
        );
        const gap = box.left - candidate.right;
        if (
          overlap > minHeight * 0.55 &&
          gap >= -height * 0.25 &&
          gap < height * 4.5
        ) {
          target = candidate;
          break;
        }
      }
      if (!target) {
        result.push({ ...box });
      } else {
        target.left = Math.min(target.left, box.left);
        target.top = Math.min(target.top, box.top);
        target.right = Math.max(target.right, box.right);
        target.bottom = Math.max(target.bottom, box.bottom);
        target.detectionConfidence = Math.min(
          target.detectionConfidence,
          box.detectionConfidence
        );
      }
    }
    return result;
  }

  async function detectTile(runtime, tile, originTop) {
    const limit = 1280;
    const scale = Math.min(1.6, limit / Math.max(tile.width, tile.height));
    const width = Math.max(32, Math.round((tile.width * scale) / 32) * 32);
    const height = Math.max(32, Math.round((tile.height * scale) / 32) * 32);
    const resized = resizeCanvas(tile, width, height, false);
    const input = canvasTensor(
      resized,
      [0.485, 0.456, 0.406],
      [0.229, 0.224, 0.225]
    );
    const name = runtime.detector.inputNames[0];
    const output = await runtime.detector.run({ [name]: input });
    const tensor = output[runtime.detector.outputNames[0]];
    const outputHeight = tensor.dims[tensor.dims.length - 2];
    const outputWidth = tensor.dims[tensor.dims.length - 1];
    return connectedTextBoxes(tensor.data, outputWidth, outputHeight).map(
      (box) => ({
        left: (box.left / outputWidth) * tile.width,
        top: originTop + (box.top / outputHeight) * tile.height,
        right: (box.right / outputWidth) * tile.width,
        bottom: originTop + (box.bottom / outputHeight) * tile.height,
        detectionConfidence: box.detectionConfidence,
      })
    );
  }

  function intersectionOverUnion(a, b) {
    const left = Math.max(a.left, b.left);
    const top = Math.max(a.top, b.top);
    const right = Math.min(a.right, b.right);
    const bottom = Math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) return 0;
    const intersection = (right - left) * (bottom - top);
    const union =
      (a.right - a.left) * (a.bottom - a.top) +
      (b.right - b.left) * (b.bottom - b.top) -
      intersection;
    return intersection / Math.max(1, union);
  }

  function deduplicateBoxes(boxes) {
    boxes.sort(
      (a, b) =>
        b.detectionConfidence - a.detectionConfidence ||
        a.top - b.top
    );
    const kept = [];
    for (const box of boxes) {
      if (kept.some((candidate) => intersectionOverUnion(box, candidate) > 0.45)) {
        continue;
      }
      kept.push(box);
    }
    return kept.sort((a, b) => a.top - b.top || a.left - b.left);
  }

  async function detectPage(runtime, source, pageIndex, pageCount) {
    const cropTop = Math.round(source.height * 0.07);
    const cropBottom = Math.round(source.height * 0.95);
    const usefulHeight = cropBottom - cropTop;
    const tileHeight = Math.min(usefulHeight, Math.max(720, source.width * 1.2));
    const overlap = Math.round(Math.min(120, tileHeight * 0.14));
    const boxes = [];
    let tileIndex = 0;
    const starts = [];
    for (let top = cropTop; top < cropBottom; top += tileHeight - overlap) {
      starts.push(Math.min(top, Math.max(cropTop, cropBottom - tileHeight)));
      if (top + tileHeight >= cropBottom) break;
    }
    for (const top of [...new Set(starts)]) {
      tileIndex += 1;
      progress(
        "detect",
        (pageIndex + (tileIndex - 1) / starts.length) / pageCount,
        `正在偵測第 ${pageIndex + 1}/${pageCount} 張截圖文字`
      );
      const height = Math.min(tileHeight, cropBottom - top);
      const tile = cropCanvas(source, 0, top, source.width, height);
      boxes.push(...(await detectTile(runtime, tile, top)));
    }
    return deduplicateBoxes(boxes);
  }

  function fixedRecognitionWidth(session, fallback) {
    const metadata = session.inputMetadata[session.inputNames[0]];
    const dimensions = metadata && metadata.dimensions;
    const width = dimensions && Number(dimensions[3]);
    return Number.isFinite(width) && width > 0 ? width : fallback;
  }

  function decodeCtc(tensor, dictionary) {
    const classCount = tensor.dims[tensor.dims.length - 1];
    const timeSteps = tensor.data.length / classCount;
    let previous = -1;
    let text = "";
    let confidence = 0;
    let emitted = 0;
    for (let step = 0; step < timeSteps; step += 1) {
      const offset = step * classCount;
      let bestIndex = 0;
      let bestValue = -Infinity;
      let max = -Infinity;
      let rawSum = 0;
      for (let index = 0; index < classCount; index += 1) {
        rawSum += tensor.data[offset + index];
        max = Math.max(max, tensor.data[offset + index]);
        if (tensor.data[offset + index] > bestValue) {
          bestValue = tensor.data[offset + index];
          bestIndex = index;
        }
      }
      if (bestIndex !== 0 && bestIndex !== previous) {
        const probabilities =
          bestValue >= 0 &&
          bestValue <= 1.001 &&
          rawSum >= 0.98 &&
          rawSum <= 1.02;
        if (probabilities) {
          confidence += bestValue;
        } else {
          let sum = 0;
          for (let index = 0; index < classCount; index += 1) {
            sum += Math.exp(tensor.data[offset + index] - max);
          }
          confidence += Math.exp(bestValue - max) / Math.max(sum, 1e-9);
        }
        emitted += 1;
        if (bestIndex - 1 < dictionary.length) {
          text += dictionary[bestIndex - 1];
        } else if (bestIndex - 1 === dictionary.length) {
          text += " ";
        }
      }
      previous = bestIndex;
    }
    return {
      text: text.replace(/\s+/g, " ").trim(),
      confidence: emitted === 0 ? 0 : confidence / emitted,
    };
  }

  async function recognizeBox(runtime, source, box) {
    const padding = Math.max(2, (box.bottom - box.top) * 0.12);
    const left = Math.max(0, box.left - padding);
    const top = Math.max(0, box.top - padding);
    const right = Math.min(source.width, box.right + padding);
    const bottom = Math.min(source.height, box.bottom + padding);
    const crop = cropCanvas(source, left, top, right - left, bottom - top);
    const height = 48;
    const naturalWidth = Math.max(
      32,
      Math.min(1536, Math.ceil(((crop.width / crop.height) * height) / 32) * 32)
    );
    const width = fixedRecognitionWidth(runtime.recognizer, naturalWidth);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.fillStyle = "#fff";
    context.fillRect(0, 0, width, height);
    const drawnWidth = Math.min(
      width,
      Math.max(1, Math.round((crop.width / crop.height) * height))
    );
    context.drawImage(crop, 0, 0, drawnWidth, height);
    const input = canvasTensor(canvas, [0.5, 0.5, 0.5], [0.5, 0.5, 0.5]);
    const name = runtime.recognizer.inputNames[0];
    const output = await runtime.recognizer.run({ [name]: input });
    const decoded = decodeCtc(
      output[runtime.recognizer.outputNames[0]],
      runtime.dictionary
    );
    return {
      ...box,
      text: decoded.text,
      recognitionConfidence: decoded.confidence,
    };
  }

  function isMoney(text) {
    return /^[-−]?\s*(?:NT\s*)?\$?\s*[\d,]+(?:\.\d{1,2})?\s*$/i.test(
      text
    );
  }

  function groupRows(recognized, pageWidth, pageHeight) {
    const rows = [];
    for (const line of recognized.filter((value) => value.text)) {
      const center = (line.top + line.bottom) / 2;
      const height = line.bottom - line.top;
      let target = null;
      for (let index = rows.length - 1; index >= 0; index -= 1) {
        const row = rows[index];
        if (line.top - row.bottom > height) break;
        const rowCenter = (row.top + row.bottom) / 2;
        if (
          Math.abs(center - rowCenter) <=
          Math.max(height, row.bottom - row.top) * 0.55
        ) {
          target = row;
          break;
        }
      }
      if (!target) {
        target = { components: [], ...line };
        rows.push(target);
      }
      target.components.push(line);
      target.left = Math.min(target.left, line.left);
      target.top = Math.min(target.top, line.top);
      target.right = Math.max(target.right, line.right);
      target.bottom = Math.max(target.bottom, line.bottom);
      target.detectionConfidence = Math.min(
        target.detectionConfidence,
        line.detectionConfidence
      );
      target.recognitionConfidence = Math.min(
        target.recognitionConfidence,
        line.recognitionConfidence
      );
    }
    rows.sort((a, b) => a.top - b.top || a.left - b.left);
    for (const row of rows) {
      row.components.sort((a, b) => a.left - b.left);
      row.components = row.components.filter(
        (component, index, values) =>
          !values
            .slice(0, index)
            .some(
              (previous) =>
                previous.text === component.text &&
                Math.abs(previous.left - component.left) <
                  Math.max(
                    previous.right - previous.left,
                    component.right - component.left
                  ) *
                    0.35
            )
      );
      row.text = row.components.map((value) => value.text).join(" ").trim();
      const leftRatio = row.left / pageWidth;
      const hasAmount = row.components.some(
        (value) => value.left / pageWidth > 0.58 && isMoney(value.text)
      );
      row.kind =
        !hasAmount &&
        leftRatio > 0.12 &&
        leftRatio < 0.7 &&
        !/[（(]\s*您\s*[)）]/.test(row.text)
          ? "modifier"
          : "text";
      row.normalized = {
        text: row.kind === "modifier" ? `[選項] ${row.text}` : row.text,
        left: row.left / pageWidth,
        top: row.top / pageHeight,
        right: row.right / pageWidth,
        bottom: row.bottom / pageHeight,
        polygon: [
          { x: row.left / pageWidth, y: row.top / pageHeight },
          { x: row.right / pageWidth, y: row.top / pageHeight },
          { x: row.right / pageWidth, y: row.bottom / pageHeight },
          { x: row.left / pageWidth, y: row.bottom / pageHeight },
        ],
        confidence: Math.min(
          row.detectionConfidence,
          row.recognitionConfidence
        ),
        detectionConfidence: row.detectionConfidence,
        recognitionConfidence: row.recognitionConfidence,
        kind: "text",
        engineVersion: ENGINE_VERSION,
      };
    }
    return rows;
  }

  async function recognizePage(runtime, image, pageIndex, pageCount) {
    const source = imageCanvas(image);
    const boxes = await detectPage(runtime, source, pageIndex, pageCount);
    const recognized = [];
    for (let index = 0; index < boxes.length; index += 1) {
      progress(
        "recognize",
        (pageIndex + index / Math.max(1, boxes.length)) / pageCount,
        `正在辨識第 ${pageIndex + 1}/${pageCount} 張截圖，第 ${
          index + 1
        }/${boxes.length} 列`,
        index + 1,
        boxes.length,
        runtime.engineLabel
      );
      recognized.push(await recognizeBox(runtime, source, boxes[index]));
    }
    const rows = groupRows(recognized, source.width, source.height);
    const lines = rows.map((row) => row.normalized);
    for (const row of rows) {
      for (const component of row.components) {
        if (
          component.left / source.width > 0.58 &&
          isMoney(component.text)
        ) {
          lines.push({
            text: component.text,
            left: component.left / source.width,
            top: component.top / source.height,
            right: component.right / source.width,
            bottom: component.bottom / source.height,
            polygon: [
              {
                x: component.left / source.width,
                y: component.top / source.height,
              },
              {
                x: component.right / source.width,
                y: component.top / source.height,
              },
              {
                x: component.right / source.width,
                y: component.bottom / source.height,
              },
              {
                x: component.left / source.width,
                y: component.bottom / source.height,
              },
            ],
            confidence: Math.min(
              component.detectionConfidence,
              component.recognitionConfidence
            ),
            detectionConfidence: component.detectionConfidence,
            recognitionConfidence: component.recognitionConfidence,
            kind: "amount",
            engineVersion: ENGINE_VERSION,
          });
        }
      }
    }
    return {
      pageIndex,
      text: rows.map((row) => row.normalized.text).join("\n"),
      lines,
      engineVersion: ENGINE_VERSION,
      executionProvider: runtime.engine,
    };
  }

  async function loadTesseractWorker() {
    if (tesseractWorkerPromise) return tesseractWorkerPromise;
    tesseractWorkerPromise = (async () => {
      if (!window.Tesseract) {
        throw new Error("Tesseract OCR 尚未載入");
      }
      progress(
        "fallback",
        0.02,
        "正在準備 iPhone 低記憶體 OCR",
        0,
        0,
        "Tesseract.js"
      );
      const worker = await Tesseract.createWorker(["chi_tra", "eng"], 1, {
        workerPath: `${TESSERACT_ROOT}worker.min.js`,
        corePath: `${TESSERACT_ROOT}core/`,
        langPath: `${TESSERACT_ROOT}lang`,
        gzip: true,
        logger: (message) => {
          const value = Number(message.progress) || 0;
          progress(
            "fallback",
            0.05 + value * 0.35,
            `正在準備低記憶體 OCR ${Math.round(value * 100)}%`,
            0,
            0,
            "Tesseract.js"
          );
        },
      });
      await worker.setParameters({
        tessedit_pageseg_mode: "6",
        preserve_interword_spaces: "1",
        user_defined_dpi: "300",
      });
      return worker;
    })();
    try {
      return await tesseractWorkerPromise;
    } catch (error) {
      tesseractWorkerPromise = null;
      throw error;
    }
  }

  async function prepareTesseractCanvas(source) {
    const image = await loadImage(source);
    const cropTop = Math.round(image.naturalHeight * 0.07);
    const cropBottom = Math.round(image.naturalHeight * 0.94);
    const scale = Math.min(
      2,
      Math.max(1, 1180 / Math.max(1, image.naturalWidth))
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(
      1,
      Math.round((cropBottom - cropTop) * scale)
    );
    const context = canvas.getContext("2d", { willReadFrequently: true });
    context.fillStyle = "#fff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(
      image,
      0,
      cropTop,
      image.naturalWidth,
      cropBottom - cropTop,
      0,
      0,
      canvas.width,
      canvas.height
    );
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
    for (let index = 0; index < pixels.data.length; index += 4) {
      const gray =
        pixels.data[index] * 0.299 +
        pixels.data[index + 1] * 0.587 +
        pixels.data[index + 2] * 0.114;
      const contrasted = Math.max(0, Math.min(255, (gray - 128) * 1.25 + 128));
      pixels.data[index] = contrasted;
      pixels.data[index + 1] = contrasted;
      pixels.data[index + 2] = contrasted;
    }
    context.putImageData(pixels, 0, 0);
    return canvas;
  }

  async function recognizeWithTesseract(sources, originalError) {
    console.warn("PP-OCR unavailable; using Tesseract fallback", originalError);
    const worker = await loadTesseractWorker();
    const pages = [];
    for (let pageIndex = 0; pageIndex < sources.length; pageIndex += 1) {
      progress(
        "recognize",
        0.4 + (pageIndex / sources.length) * 0.55,
        `iPhone 低記憶體 OCR 正在辨識第 ${pageIndex + 1}/${
          sources.length
        } 張截圖`,
        pageIndex + 1,
        sources.length,
        "Tesseract.js"
      );
      const prepared = await prepareTesseractCanvas(sources[pageIndex]);
      const result = await worker.recognize(prepared);
      pages.push({
        pageIndex,
        text: result.data.text || "",
        lines: [],
        engineVersion: "tesseract.js-7-chi_tra+eng-preprocessed-v2",
        executionProvider: "wasm",
      });
      prepared.width = 1;
      prepared.height = 1;
    }
    progress(
      "parse",
      1,
      "正在解析與對帳",
      0,
      0,
      "Tesseract.js"
    );
    return pages;
  }

  window.kgzOcrRecognize = async function (imagesJson) {
    const sources = JSON.parse(imagesJson);
    if (!Array.isArray(sources) || sources.length === 0) {
      throw new Error("未提供截圖");
    }
    let runtime;
    let pages;
    if (needsIphoneLowMemoryMode()) {
      await deleteOldModelCaches();
      pages = await recognizeWithTesseract(
        sources,
        new Error("iPhone uses the low-memory OCR path")
      );
    } else try {
      // Safari supports the WASM execution provider even when WebGPU is not
      // available. Always try PP-OCR first so mobile and desktop use the same
      // detector and recognizer; Tesseract remains the runtime-failure fallback.
      runtime = await loadRuntime();
      pages = [];
      for (let pageIndex = 0; pageIndex < sources.length; pageIndex += 1) {
        const image = await loadImage(sources[pageIndex]);
        pages.push(
          await recognizePage(runtime, image, pageIndex, sources.length)
        );
      }
    } catch (error) {
      runtime = null;
      pages = await recognizeWithTesseract(sources, error);
    }
    progress(
      "parse",
      1,
      "正在解析與對帳",
      0,
      0,
      runtime ? runtime.engineLabel : "Tesseract.js"
    );
    return JSON.stringify(pages);
  };
})();
