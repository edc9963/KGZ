import 'repositories.dart';
import 'ocr_models.dart';
import 'local_ocr_worker_stub.dart'
    if (dart.library.js_interop) 'local_ocr_worker_web.dart'
    as implementation;

Future<List<OcrPage>> recognizeImportImages(
  List<ImportImage> images, {
  OcrProgressCallback? onProgress,
}) => implementation.recognizeImportImages(images, onProgress: onProgress);
