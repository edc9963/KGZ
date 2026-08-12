import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

import 'import_image_picker_models.dart';

Future<Uint8List> _readFile(File file) {
  final completer = Completer<Uint8List>();
  final reader = FileReader();
  reader.onLoadEnd.first.then((_) {
    final buffer = (reader.result as JSArrayBuffer?)?.toDart;
    if (buffer == null) {
      completer.completeError(StateError('無法讀取 ${file.name}'));
    } else {
      completer.complete(buffer.asUint8List());
    }
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}

Future<List<PickedImportImage>?> pickImportImages() async {
  final result = Completer<List<PickedImportImage>?>();
  final input = HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/webp'
    ..multiple = true
    ..style.display = 'none';
  document.body?.append(input);

  var changed = false;
  input.onChange.first.then((_) async {
    if (changed || result.isCompleted) return;
    changed = true;
    try {
      final files = input.files;
      if (files == null || files.length == 0) {
        result.complete(null);
        return;
      }
      final images = <PickedImportImage>[];
      for (var index = 0; index < files.length; index++) {
        final file = files.item(index);
        if (file == null) continue;
        final bytes = await _readFile(file);
        images.add(
          PickedImportImage(name: file.name, size: bytes.length, bytes: bytes),
        );
      }
      if (!result.isCompleted) result.complete(images);
    } on Object catch (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }
  });

  input.addEventListener(
    'cancel',
    ((Event _) {
      if (!changed && !result.isCompleted) result.complete(null);
    }).toJS,
  );
  input.click();
  try {
    return await result.future;
  } finally {
    input.remove();
  }
}
