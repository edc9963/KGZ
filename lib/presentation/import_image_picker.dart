import 'import_image_picker_models.dart';
import 'import_image_picker_stub.dart'
    if (dart.library.js_interop) 'import_image_picker_web.dart'
    as implementation;

Future<List<PickedImportImage>?> pickImportImages() =>
    implementation.pickImportImages();
