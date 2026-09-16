import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/detected_item.dart';
import '../services/count_api_service.dart';
import '../services/on_device_counter_service.dart';
import '../services/tts_service.dart';
import '../widgets/bounding_box_overlay.dart';

class ImageAuditScreen extends StatefulWidget {
  final CountApiService apiService;
  final OnDeviceCounterService onDeviceService;
  final bool isOnDeviceMode;
  final String selectedMode;
  final double sensitivity;

  const ImageAuditScreen({
    super.key,
    required this.apiService,
    required this.onDeviceService,
    this.isOnDeviceMode = true,
    this.selectedMode = 'jewelry_pin',
    this.sensitivity = 0.5,
  });

  @override
  State<ImageAuditScreen> createState() => _ImageAuditScreenState();
}

class _ImageAuditScreenState extends State<ImageAuditScreen> {
  final ImagePicker _picker = ImagePicker();
  final TtsService _ttsService = TtsService();

  Uint8List? _imageBytes;
  CountResult _result = CountResult.empty();
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _isLoading = true;
      });

      CountResult res;
      if (widget.isOnDeviceMode) {
        res = await widget.onDeviceService.processImageBytes(
          bytes,
          sensitivity: widget.sensitivity,
          mode: widget.selectedMode,
        );
      } else {
        res = await widget.apiService.countImageBytes(bytes);
      }

      if (!mounted) return;
      setState(() {
        _result = res;
        _isLoading = false;
      });

      _ttsService.announceCount(res.count, force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking image: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text("Photo Count Audit", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          if (_result.count > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_result.count} Pieces",
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _imageBytes == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded, size: 72, color: Colors.white24),
                        const SizedBox(height: 16),
                        const Text(
                          "Select or capture an image to audit",
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: const Icon(Icons.photo_library),
                              label: const Text("Gallery"),
                              onPressed: () => _pickImage(ImageSource.gallery),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FF9D),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text("Take Photo"),
                              onPressed: () => _pickImage(ImageSource.camera),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_imageBytes!, fit: BoxFit.contain),
                      if (!_isLoading)
                        BoundingBoxOverlay(
                          result: _result,
                          previewSize: Size(
                            _result.processedWidth.toDouble(),
                            _result.processedHeight.toDouble(),
                          ),
                        ),
                      if (_isLoading)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Color(0xFF00FF9D)),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_imageBytes != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF0F172A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Detected: ${_result.count} items (${_result.latencyMs.toInt()}ms)",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text("Retake"),
                        onPressed: () => _pickImage(ImageSource.camera),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
