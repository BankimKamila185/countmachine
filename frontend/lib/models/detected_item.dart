import 'dart:ui';

class DetectedItem {
  final int id;
  final Offset center;
  final Rect bbox;
  final Rect gemBbox;
  final double area;
  final double confidence;
  final String type;

  DetectedItem({
    required this.id,
    required this.center,
    required this.bbox,
    required this.gemBbox,
    required this.area,
    required this.confidence,
    required this.type,
  });

  factory DetectedItem.fromJson(Map<String, dynamic> json) {
    final centerList = List<num>.from(json['center'] ?? [0, 0]);
    final bboxList = List<num>.from(json['bbox'] ?? [0, 0, 0, 0]);
    final gemBboxList = List<num>.from(json['gem_bbox'] ?? [0, 0, 0, 0]);

    return DetectedItem(
      id: json['id'] ?? 0,
      center: Offset(centerList[0].toDouble(), centerList[1].toDouble()),
      bbox: Rect.fromLTWH(
        bboxList[0].toDouble(),
        bboxList[1].toDouble(),
        bboxList[2].toDouble(),
        bboxList[3].toDouble(),
      ),
      gemBbox: Rect.fromLTWH(
        gemBboxList[0].toDouble(),
        gemBboxList[1].toDouble(),
        gemBboxList[2].toDouble(),
        gemBboxList[3].toDouble(),
      ),
      area: (json['area'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      type: json['type'] ?? 'jewelry_pin',
    );
  }
}

class CountResult {
  final int count;
  final List<DetectedItem> items;
  final int processedWidth;
  final int processedHeight;
  final double latencyMs;

  CountResult({
    required this.count,
    required this.items,
    required this.processedWidth,
    required this.processedHeight,
    this.latencyMs = 0.0,
  });

  factory CountResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return CountResult(
      count: json['count'] ?? 0,
      items: rawItems.map((e) => DetectedItem.fromJson(e as Map<String, dynamic>)).toList(),
      processedWidth: json['processed_width'] ?? 640,
      processedHeight: json['processed_height'] ?? 480,
      latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory CountResult.empty() {
    return CountResult(
      count: 0,
      items: [],
      processedWidth: 640,
      processedHeight: 480,
    );
  }
}
