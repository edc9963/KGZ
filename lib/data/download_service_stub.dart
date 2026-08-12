import 'dart:convert';

import 'repositories.dart';

class BrowserCsvExportService implements CsvExportService {
  @override
  Future<void> export(String fileName, List<List<Object?>> rows) async {
    // Tests and non-web targets can still validate the generated CSV.
    encodeCsv(rows);
  }
}

String encodeCsv(List<List<Object?>> rows) {
  String cell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  return '\uFEFF${rows.map((row) => row.map(cell).join(',')).join('\r\n')}';
}

List<int> encodeCsvBytes(List<List<Object?>> rows) =>
    utf8.encode(encodeCsv(rows));
