// ignore_for_file: avoid_web_libraries_in_flutter

// ignore: deprecated_member_use
import 'dart:html' as html;

import 'download_service_stub.dart' hide BrowserCsvExportService;
import 'repositories.dart';

class BrowserCsvExportService implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {
    final blob = html.Blob([encodeCsvBytes(rows)], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
