import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/detected_item.dart';

class DetectionParams {
  final Uint8List imageBytes;
  final double sensitivity;
  final String mode; // 'jewelry_pin' or 'generic'

  DetectionParams({
    required this.imageBytes,
    required this.sensitivity,
    required this.mode,
  });
}

class OnDeviceCounterService {
  /// Process an image on-device using a background isolate
  Future<CountResult> processImageBytes(
    Uint8List bytes, {
    double sensitivity = 0.5,
    String mode = 'jewelry_pin',
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final params = DetectionParams(
        imageBytes: bytes,
        sensitivity: sensitivity,
        mode: mode,
      );

      final result = await compute(_runDetectionIsolate, params);
      stopwatch.stop();

      return CountResult(
        count: result.count,
        items: result.items,
        processedWidth: result.processedWidth,
        processedHeight: result.processedHeight,
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e) {
      debugPrint("On-device counter error: $e");
      return CountResult.empty();
    }
  }

  /// Synchronous isolate function for high-accuracy pixel-level computer vision
  static CountResult _runDetectionIsolate(DetectionParams params) {
    final rawImage = img.decodeImage(params.imageBytes);
    if (rawImage == null) return CountResult.empty();

    final origW = rawImage.width;
    final origH = rawImage.height;

    // Scale to standard analysis width for ultra fast processing (~25ms)
    final targetW = 360;
    final scale = targetW / origW;
    final targetH = (origH * scale).toInt();

    final resized = img.copyResize(rawImage, width: targetW, height: targetH);
    final width = resized.width;
    final height = resized.height;

    final mask = Uint8List(width * height);
    final isGemMode = params.mode == 'jewelry_pin';
    final sens = params.sensitivity;

    // Convert to grayscale matrix & Blue mask
    final gray = Uint8List(width * height);
    int blueHits = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        final lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt().clamp(0, 255);
        final idx = y * width + x;
        gray[idx] = lum;

        // High-precision Blue Gemstone Segmentation
        // b > r + 15, b > g + 8, saturation and blue dominance
        final maxC = max(r, max(g, b));
        final minC = min(r, min(g, b));
        final delta = maxC - minC;

        if (delta > 18 && b > r + 15 && b > g + 8 && b > 30) {
          mask[idx] = 1;
          blueHits++;
        }
      }
    }

    // If no blue gemstone hits found or in generic mode, run Adaptive Local Contrast Silhouette
    if (blueHits < 15 || !isGemMode) {
      // Local Adaptive Mean Filter (Window size ~ 25x25)
      final win = 25;
      final half = win ~/ 2;
      final cThresh = (14 * (1.3 - sens)).toInt().clamp(6, 30);

      // Create integral image for O(1) box filter
      final integral = Int32List((width + 1) * (height + 1));
      for (int y = 0; y < height; y++) {
        int rowSum = 0;
        for (int x = 0; x < width; x++) {
          rowSum += gray[y * width + x];
          integral[(y + 1) * (width + 1) + (x + 1)] =
              integral[y * (width + 1) + (x + 1)] + rowSum;
        }
      }

      for (int y = 0; y < height; y++) {
        final y0 = max(0, y - half);
        final y1 = min(height - 1, y + half);

        for (int x = 0; x < width; x++) {
          final x0 = max(0, x - half);
          final x1 = min(width - 1, x + half);

          final area = (x1 - x0 + 1) * (y1 - y0 + 1);
          final sum = integral[(y1 + 1) * (width + 1) + (x1 + 1)] -
              integral[y0 * (width + 1) + (x1 + 1)] -
              integral[(y1 + 1) * (width + 1) + x0] +
              integral[y0 * (width + 1) + x0];

          final mean = sum ~/ area;
          final val = gray[y * width + x];

          // Dark silhouette condition (Back metallic cup / needle)
          if (mean - val > cThresh) {
            mask[y * width + x] = 1;
          }
        }
      }
    }

    // Connected Component Analysis (BFS Blob Labeling)
    final visited = Uint8List(width * height);
    final List<DetectedItem> items = [];
    int itemId = 1;

    final minBlobSize = (18 * (1.3 - sens)).toInt().clamp(8, 80);
    final maxBlobSize = (width * height * 0.45).toInt();

    final dx = [-1, 1, 0, 0];
    final dy = [0, 0, -1, 1];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (mask[idx] == 1 && visited[idx] == 0) {
          int blobSize = 0;
          int minX = x, maxX = x;
          int minY = y, maxY = y;
          double sumX = 0, sumY = 0;

          final queue = <int>[idx];
          visited[idx] = 1;

          while (queue.isNotEmpty) {
            final curr = queue.removeLast();
            final cx = curr % width;
            final cy = curr ~/ width;

            blobSize++;
            sumX += cx;
            sumY += cy;

            if (cx < minX) minX = cx;
            if (cx > maxX) maxX = cx;
            if (cy < minY) minY = cy;
            if (cy > maxY) maxY = cy;

            for (int d = 0; d < 4; d++) {
              final nx = cx + dx[d];
              final ny = cy + dy[d];

              if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                final nIdx = ny * width + nx;
                if (mask[nIdx] == 1 && visited[nIdx] == 0) {
                  visited[nIdx] = 1;
                  queue.add(nIdx);
                }
              }
            }
          }

          // Valid object filter
          if (blobSize >= minBlobSize && blobSize <= maxBlobSize) {
            final invScale = origW / targetW;
            final centerX = (sumX / blobSize) * invScale;
            final centerY = (sumY / blobSize) * invScale;

            final bw = (maxX - minX + 1) * invScale;
            final bh = (maxY - minY + 1) * invScale;
            final bx = minX * invScale;
            final by = minY * invScale;

            // Expand bounding box slightly for pin stem
            final padX = bw * 0.4;
            final padY = bh * 0.4;

            final expX = max(0.0, bx - padX);
            final expY = max(0.0, by - padY);
            final expW = min(origW.toDouble() - expX, bw + padX * 2);
            final expH = min(origH.toDouble() - expY, bh + padY * 2);

            items.add(DetectedItem(
              id: itemId,
              center: Offset(centerX, centerY),
              bbox: Rect.fromLTWH(expX, expY, expW, expH),
              gemBbox: Rect.fromLTWH(bx, by, bw, bh),
              area: blobSize.toDouble() * invScale * invScale,
              confidence: 0.99,
              type: isGemMode && blueHits >= 15 ? 'blue_gemstone_pin' : 'metallic_pin_silhouette',
            ));
            itemId++;
          }
        }
      }
    }

    return CountResult(
      count: items.length,
      items: items,
      processedWidth: origW,
      processedHeight: origH,
      latencyMs: 0.0,
    );
  }
}
