import 'repositories.dart';
import 'ocr_models.dart';

Future<List<OcrPage>> recognizeImportImages(
  List<ImportImage> images, {
  OcrProgressCallback? onProgress,
}) {
  throw UnsupportedError('本機截圖辨識目前只支援 Web 版本');
}
