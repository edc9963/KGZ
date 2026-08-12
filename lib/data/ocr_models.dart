class OcrPoint {
  const OcrPoint({required this.x, required this.y});

  final double x;
  final double y;

  factory OcrPoint.fromJson(Map<String, dynamic> json) => OcrPoint(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
  );
}

class OcrLine {
  const OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.confidence,
    required this.kind,
    this.polygon = const [],
    this.detectionConfidence,
    this.recognitionConfidence,
    this.engineVersion = '',
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;
  final String kind;
  final List<OcrPoint> polygon;
  final double? detectionConfidence;
  final double? recognitionConfidence;
  final String engineVersion;

  double get centerY => (top + bottom) / 2;

  factory OcrLine.fromJson(Map<String, dynamic> json) => OcrLine(
    text: json['text'] as String? ?? '',
    left: (json['left'] as num?)?.toDouble() ?? 0,
    top: (json['top'] as num?)?.toDouble() ?? 0,
    right: (json['right'] as num?)?.toDouble() ?? 0,
    bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    kind: json['kind'] as String? ?? 'text',
    polygon: [
      for (final point in json['polygon'] as List? ?? const [])
        OcrPoint.fromJson(Map<String, dynamic>.from(point as Map)),
    ],
    detectionConfidence: (json['detectionConfidence'] as num?)?.toDouble(),
    recognitionConfidence: (json['recognitionConfidence'] as num?)?.toDouble(),
    engineVersion: json['engineVersion'] as String? ?? '',
  );
}

class OcrPage {
  const OcrPage({
    required this.pageIndex,
    required this.text,
    required this.lines,
    this.engineVersion = '',
    this.executionProvider = '',
  });

  final int pageIndex;
  final String text;
  final List<OcrLine> lines;
  final String engineVersion;
  final String executionProvider;

  factory OcrPage.fromJson(Map<String, dynamic> json) => OcrPage(
    pageIndex: json['pageIndex'] as int? ?? 0,
    text: json['text'] as String? ?? '',
    lines: [
      for (final line in json['lines'] as List? ?? const [])
        OcrLine.fromJson(Map<String, dynamic>.from(line as Map)),
    ],
    engineVersion: json['engineVersion'] as String? ?? '',
    executionProvider: json['executionProvider'] as String? ?? '',
  );
}

class OcrProgress {
  const OcrProgress({
    required this.stage,
    required this.progress,
    required this.message,
    this.current = 0,
    this.total = 0,
    this.engine = '',
  });

  final String stage;
  final double progress;
  final String message;
  final int current;
  final int total;
  final String engine;

  factory OcrProgress.fromJson(Map<String, dynamic> json) => OcrProgress(
    stage: json['stage'] as String? ?? '',
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    message: json['message'] as String? ?? '正在辨識',
    current: (json['current'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    engine: json['engine'] as String? ?? '',
  );
}

typedef OcrProgressCallback = void Function(OcrProgress progress);
