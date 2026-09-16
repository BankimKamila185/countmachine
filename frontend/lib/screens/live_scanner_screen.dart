import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/detected_item.dart';
import '../services/count_api_service.dart';
import '../services/on_device_counter_service.dart';
import '../services/tts_service.dart';
import '../widgets/bounding_box_overlay.dart';
import 'image_audit_screen.dart';

class LiveScannerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const LiveScannerScreen({super.key, required this.cameras});

  @override
  State<LiveScannerScreen> createState() => _LiveScannerScreenState();
}

class _LiveScannerScreenState extends State<LiveScannerScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isTorchOn = false;
  bool _isProcessingFrame = false;

  final CountApiService _apiService = CountApiService();
  final OnDeviceCounterService _onDeviceService = OnDeviceCounterService();
  final TtsService _ttsService = TtsService();

  CountResult _currentResult = CountResult.empty();
  double _sensitivity = 0.50;
  String _selectedMode = 'jewelry_pin';
  bool _isOnDeviceMode = true; // Standalone phone mode by default
  bool _isConnected = false;
  Timer? _frameTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    if (!_isOnDeviceMode) {
      _connectBackend();
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    final camera = widget.cameras[_selectedCameraIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      _startFrameCaptureLoop();
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  void _connectBackend() {
    _apiService.connectWebSocket(
      onData: (result) {
        if (!mounted || _isOnDeviceMode) return;
        setState(() {
          _isConnected = true;
          _currentResult = result;
        });
        _ttsService.announceCount(result.count);
      },
      onError: (err) {
        if (!mounted) return;
        setState(() => _isConnected = false);
      },
    );
  }

  void _startFrameCaptureLoop() {
    // Process snapshot loop for real-time live detection
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 140), (_) async {
      if (_controller == null || !_controller!.value.isInitialized || _isProcessingFrame) {
        return;
      }

      _isProcessingFrame = true;
      try {
        final imageFile = await _controller!.takePicture();
        final bytes = await imageFile.readAsBytes();

        if (_isOnDeviceMode) {
          // Process 100% on-device inside phone CPU
          final result = await _onDeviceService.processImageBytes(
            bytes,
            sensitivity: _sensitivity,
            mode: _selectedMode,
          );
          if (mounted) {
            setState(() {
              _currentResult = result;
            });
            _ttsService.announceCount(result.count);
          }
        } else {
          // Stream to remote server
          _apiService.sendFrame(bytes, sensitivity: _sensitivity, mode: _selectedMode);
        }
      } catch (e) {
        // Frame capture skipped during transitions
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _toggleTorch() async {
    if (_controller == null) return;
    try {
      _isTorchOn = !_isTorchOn;
      await _controller!.setFlashMode(_isTorchOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint("Torch toggle error: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    await _controller?.dispose();
    _initializeCamera();
  }

  void _showSettingsDialog() {
    final hostController = TextEditingController(text: _apiService.host);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Scanner Settings",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Engine Toggle (On-Device vs Server)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isOnDeviceMode ? const Color(0xFF00FF9D).withOpacity(0.5) : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _isOnDeviceMode ? Icons.phone_android : Icons.cloud_outlined,
                                  color: _isOnDeviceMode ? const Color(0xFF00FF9D) : Colors.amberAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isOnDeviceMode ? "On-Device Engine (Standalone)" : "Server Engine",
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isOnDeviceMode,
                              activeColor: const Color(0xFF00FF9D),
                              onChanged: (val) {
                                setModalState(() => _isOnDeviceMode = val);
                                setState(() => _isOnDeviceMode = val);
                                if (!val) {
                                  _connectBackend();
                                }
                              },
                            ),
                          ],
                        ),
                        Text(
                          _isOnDeviceMode
                              ? "⚡ Running 100% on phone CPU. No backend or Wi-Fi required."
                              : "🌐 Connected to Python FastAPI backend server over network.",
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  if (!_isOnDeviceMode) ...[
                    const SizedBox(height: 16),
                    const Text("AI Server Address (IP:Port)", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: hostController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        hintText: "127.0.0.1:8000 or 192.168.1.X:8000",
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, color: Color(0xFF00FF9D)),
                          onPressed: () {
                            _apiService.host = hostController.text.trim();
                            _connectBackend();
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Detection Sensitivity", style: TextStyle(color: Colors.white70)),
                      Text("${(_sensitivity * 100).toInt()}%", style: const TextStyle(color: Color(0xFF00FF9D), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _sensitivity,
                    min: 0.1,
                    max: 1.0,
                    activeColor: const Color(0xFF00FF9D),
                    inactiveColor: Colors.white24,
                    onChanged: (val) {
                      setModalState(() => _sensitivity = val);
                      setState(() => _sensitivity = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text("Detection Mode", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedMode,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E293B),
                      underline: const SizedBox(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      items: const [
                        DropdownMenuItem(value: 'jewelry_pin', child: Text("Blue Gemstone Jewelry Pin")),
                        DropdownMenuItem(value: 'generic', child: Text("Generic Contrast Objects")),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _selectedMode = val);
                          setState(() => _selectedMode = val);
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _controller?.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Stream View
            Positioned.fill(
              child: _controller != null && _controller!.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.previewSize?.height ?? 1,
                        height: _controller!.value.previewSize?.width ?? 1,
                        child: CameraPreview(_controller!),
                      ),
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00FF9D)),
                    ),
            ),

            // Neon Bounding Boxes Overlay
            if (_currentResult.count > 0 && _controller != null && _controller!.value.isInitialized)
              Positioned.fill(
                child: BoundingBoxOverlay(
                  result: _currentResult,
                  previewSize: Size(
                    _currentResult.processedWidth.toDouble(),
                    _currentResult.processedHeight.toDouble(),
                  ),
                ),
              ),

            // Top HUD Status Bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mode Indicator Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isOnDeviceMode ? const Color(0xFF00FF9D) : (_isConnected ? Colors.blueAccent : Colors.orange),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isOnDeviceMode ? const Color(0xFF00FF9D) : (_isConnected ? Colors.blueAccent : Colors.orange),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isOnDeviceMode ? "ON-DEVICE (OFFLINE)" : (_isConnected ? "SERVER LIVE" : "CONNECTING..."),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top Action Buttons
                  Row(
                    children: [
                      _buildHeaderCircleButton(
                        icon: _isTorchOn ? Icons.flash_on : Icons.flash_off,
                        color: _isTorchOn ? Colors.amberAccent : Colors.white70,
                        onTap: _toggleTorch,
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderCircleButton(
                        icon: Icons.flip_camera_ios,
                        color: Colors.white70,
                        onTap: _switchCamera,
                      ),
                      const SizedBox(width: 8),
                      _buildHeaderCircleButton(
                        icon: Icons.tune,
                        color: Colors.white70,
                        onTap: _showSettingsDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Big Live Counter Display HUD (Center-Bottom)
            Positioned(
              bottom: 32,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0F172A).withOpacity(0.92),
                          const Color(0xFF1E293B).withOpacity(0.92),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF00FF9D).withOpacity(0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF9D).withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "TOTAL COUNT",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  "${_currentResult.count}",
                                  style: const TextStyle(
                                    color: Color(0xFF00FF9D),
                                    fontSize: 42,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "PIECES",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Announce / Photo Audit Switch Button
                        Row(
                          children: [
                            IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF00FF9D).withOpacity(0.15),
                                foregroundColor: const Color(0xFF00FF9D),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.all(12),
                              ),
                              icon: const Icon(Icons.volume_up_rounded, size: 26),
                              onPressed: () => _ttsService.announceCount(_currentResult.count, force: true),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF38BDF8).withOpacity(0.15),
                                foregroundColor: const Color(0xFF38BDF8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.all(12),
                              ),
                              icon: const Icon(Icons.photo_library_outlined, size: 26),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ImageAuditScreen(
                                      apiService: _apiService,
                                      onDeviceService: _onDeviceService,
                                      isOnDeviceMode: _isOnDeviceMode,
                                      selectedMode: _selectedMode,
                                      sensitivity: _sensitivity,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 22),
        onPressed: onTap,
      ),
    );
  }
}
