import 'dart:convert';
import 'dart:js_interop';

import 'ocr_models.dart';
import 'repositories.dart';

@JS('kgzOcrRecognize')
external JSPromise<JSString> _recognize(JSString imagesJson);

@JS('kgzOcrProgress')
external set _progressHandler(JSFunction? callback);

Future<List<OcrPage>> recognizeImportImages(
  List<ImportImage> images, {
  OcrProgressCallback? onProgress,
}) async {
  final payload = jsonEncode([
    for (final image in images)
      'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
  ]);
  final callback = ((JSString encoded) {
    if (onProgress == null) return;
    final decoded = jsonDecode(encoded.toDart);
    if (decoded is Map) {
      onProgress(OcrProgress.fromJson(Map<String, dynamic>.from(decoded)));
    }
  }).toJS;
  _progressHandler = callback;
  try {
    final encoded = (await _recognize(payload.toJS).toDart).toDart;
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw StateError('本機 OCR 沒有回傳可讀結果');
    }
    return [
      for (final page in decoded)
        OcrPage.fromJson(Map<String, dynamic>.from(page as Map)),
    ];
  } finally {
    _progressHandler = null;
  }
}
