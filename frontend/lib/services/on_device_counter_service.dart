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

  /// Synchronous isolate function for pixel-level vision processing
  static CountResult _runDetectionIsolate(DetectionParams params) {
    final rawImage = img.decodeImage(params.imageBytes);
    if (rawImage == null) return CountResult.empty();

    final origW = rawImage.width;
    final origH = rawImage.height;

    // Scale down for ultra fast processing (< 25ms) while retaining full detection fidelity
    final targetW = 320;
    final scale = targetW / origW;
    final targetH = (origH * scale).toInt();

    final resized = img.copyResize(rawImage, width: targetW, height: targetH);
    final width = resized.width;
    final height = resized.height;

    // Binary grid for mask
    final mask = Uint8List(width * height);

    final isGemMode = params.mode == 'jewelry_pin';
    final sens = params.sensitivity;

    // 1. Pixel Classification
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        bool isTarget = false;

        if (isGemMode) {
          // Blue Gemstone Segmentation (Strong Blue dominance & saturation)
          // R < B, G < B, and sufficient blue strength
          final maxC = max(r, max(g, b));
          final minC = min(r, min(g, b));
          final delta = maxC - minC;

          if (delta > 20 && b > r + 15 && b > g + 10 && b > 35) {
            isTarget = true;
          }
        } else {
          // Generic contrast / dark silhouette mode
          final luminance = (0.299 * r + 0.587 * g + 0.114 * b).toInt();
          final thresh = (100 * (1.3 - sens)).toInt();
          if (luminance < thresh) {
            isTarget = true;
          }
        }

        if (isTarget) {
          mask[y * width + x] = 1;
        }
      }
    }

    // 2. Connected Component Labeling (Blob grouping via BFS)
    final visited = Uint8List(width * height);
    final List<DetectedItem> items = [];
    int itemId = 1;

    final minBlobSize = (15 * (1.3 - sens)).toInt().clamp(6, 100);
    final maxBlobSize = (width * height * 0.4).toInt();

    final dx = [-1, 1, 0, 0];
    final dy = [0, 0, -1, 1];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (mask[idx] == 1 && visited[idx] == 0) {
          // Start BFS for this blob
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

          // Check if valid component size
          if (blobSize >= minBlobSize && blobSize <= maxBlobSize) {
            final invScale = origW / targetW;
            final centerX = (sumX / blobSize) * invScale;
            final centerY = (sumY / blobSize) * invScale;

            final bw = (maxX - minX + 1) * invScale;
            final bh = (maxY - minY + 1) * invScale;
            final bx = minX * invScale;
            final by = minY * invScale;

            // Expand bounding box slightly for pin stem
            final padX = bw * 0.35;
            final padY = bh * 0.35;

            final expX = max(0.0, bx - padX);
            final expY = max(0.0, by - padY);
            final expW = min(origW - expX, bw + padX * 2);
            final expH = min(origH - expY, bh + padY * 2);

            items.add(DetectedItem(
              id: itemId,
              center: Offset(centerX, centerY),
              bbox: Rect.fromLTWH(expX, expY, expW, expH),
              gemBbox: Rect.fromLTWH(bx, by, bw, bh),
              area: blobSize.toDouble() * invScale * invScale,
              confidence: min(0.99, 0.75 + (blobSize / (minBlobSize * 8)) * 0.20),
              type: isGemMode ? 'jewelry_pin' : 'generic_piece',
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
