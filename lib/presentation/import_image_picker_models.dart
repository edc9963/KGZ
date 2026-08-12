import 'dart:typed_data';

class PickedImportImage {
  const PickedImportImage({
    required this.name,
    required this.size,
    required this.bytes,
  });

  final String name;
  final int size;
  final Uint8List? bytes;

  String? get extension {
    final separator = name.lastIndexOf('.');
    return separator < 0 || separator == name.length - 1
        ? null
        : name.substring(separator + 1);
  }
}
