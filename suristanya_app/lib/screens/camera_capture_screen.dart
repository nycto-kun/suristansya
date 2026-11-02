import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';


import '../models/body_scan.dart';

class CameraCaptureScreen extends StatefulWidget {
  final BodyPart part;
  const CameraCaptureScreen({super.key, required this.part});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  bool _flashOn = false;
  String? _error;

  Size _canvasSize = Size.zero;
  ui.Image? _guideImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGuideImage();
    _initialize();
  }

  Future<void> _loadGuideImage() async {
    try {
      final data = await rootBundle.load(_assetPath(widget.part));
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _guideImage = frame.image);
    } catch (e) {
      debugPrint('Failed to load guide image: $e');
    }
  }

  String _assetPath(BodyPart part) {
    switch (part) {
      case BodyPart.tongue:
        return 'assets/guides/tongue.png';
      case BodyPart.palm:
        return 'assets/guides/palm.png';
      case BodyPart.nail:
        return 'assets/guides/nails.png';
      case BodyPart.eye:
        return 'assets/guides/eyepallor.png';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No cameras found on this device.';
        });
        return;
      }
      final backIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _currentIndex = backIdx == -1 ? 0 : backIdx;
      await _startCamera();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not access camera: $e';
      });
    }
  }

  Future<void> _startCamera() async {
    final camera = _cameras[_currentIndex];
    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not start camera: $e';
      });
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    await _controller?.dispose();
    _currentIndex = (_currentIndex + 1) % _cameras.length;
    if (mounted) setState(() => _initializing = true);
    await _startCamera();
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    try {
      _flashOn = !_flashOn;
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() {});
    } catch (_) {}
  }

    Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      
      // NEW: Quality Check (Brightness)
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        double brightness = 0;
        int pixelCount = decoded.width * decoded.height;
        for (int i = 0; i < pixelCount; i += 50) { // Sample fewer pixels for speed
          int x = i % decoded.width;
          int y = i ~/ decoded.width;
          var pixel = decoded.getPixel(x, y);
          brightness += (pixel.r + pixel.g + pixel.b) / 3;
        }
        brightness = brightness / (pixelCount / 50);

        if (brightness < 50) { // Too dark
          if (!mounted) return;
          setState(() => _capturing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image is too dark. Please move to a brighter area and retake.'),
              backgroundColor: Colors.red,
            ),
          );
          return; 
        }
      }

      final cropped = await _cropToGuide(file);
      if (!mounted) return;
      Navigator.pop(context, cropped);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
    }
  }

  Future<XFile> _cropToGuide(XFile file) async {
    if (_canvasSize == Size.zero) return file;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return file;

    final imgW = decoded.width.toDouble();
    final imgH = decoded.height.toDouble();
    final screenW = _canvasSize.width;
    final screenH = _canvasSize.height;

    final scale = math.max(screenW / imgW, screenH / imgH);
    final offsetX = (imgW * scale - screenW) / 2;
    final offsetY = (imgH * scale - screenH) / 2;

    final guide = _guideRect(_canvasSize);
    double px = (guide.left + offsetX) / scale;
    double py = (guide.top + offsetY) / scale;
    double pw = guide.width / scale;
    double ph = guide.height / scale;

    final padW = pw * 0.08;
    final padH = ph * 0.08;
    px -= padW;
    py -= padH;
    pw += padW * 2;
    ph += padH * 2;

    final x = px.round().clamp(0, decoded.width - 1);
    final y = py.round().clamp(0, decoded.height - 1);
    final w = pw.round().clamp(1, decoded.width - x);
    final h = ph.round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final outBytes = img.encodeJpg(cropped, quality: 90);

    if (kIsWeb) {
      return XFile.fromData(
        Uint8List.fromList(outBytes),
        mimeType: 'image/jpeg',
        name: '${widget.part.apiKey}.jpg',
      );
    }

    final tmp = await getTemporaryDirectory();
    final outPath =
        '${tmp.path}/${widget.part.apiKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final out = File(outPath);
    await out.writeAsBytes(outBytes);
    return XFile(out.path);
  }

  Rect _guideRect(Size screen) {
    final cx = screen.width / 2;
    final cy = screen.height / 2 - 20;

    switch (widget.part) {
      case BodyPart.tongue:
        return Rect.fromCenter(
          center: Offset(cx, cy),
          width: screen.width * 0.70,
          height: screen.width * 0.70,
        );
      case BodyPart.palm:
        return Rect.fromCenter(
          center: Offset(cx, cy),
          width: screen.width * 0.82,
          height: screen.width * 0.82,
        );
      case BodyPart.nail:
        return Rect.fromCenter(
          center: Offset(cx, cy),
          width: screen.width * 0.90,
          height: screen.width * 0.66,
        );
      case BodyPart.eye:
        return Rect.fromCenter(
          center: Offset(cx, cy),
          width: screen.width * 0.90,
          height: screen.width * 0.72,
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _guideImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: _buildBody());
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();
    if (_initializing || _controller == null) return _buildLoading();

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            if (_guideImage != null)
              CustomPaint(
                painter: _ImageGuidePainter(
                  image: _guideImage!,
                  rect: _guideRect(_canvasSize),
                ),
              ),
            _buildTopBar(),
            _buildInstruction(),
            _buildBottomBar(),
          ],
        );
      },
    );
  }

  Widget _buildPreview() {
    final c = _controller!;
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.previewSize!.height,
            height: c.value.previewSize!.width,
            child: CameraPreview(c),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              _circleButton(
                icon: _flashOn
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
                onTap: _toggleFlash,
              ),
              const SizedBox(width: 8),
              if (_cameras.length > 1)
                _circleButton(
                  icon: Icons.cameraswitch_rounded,
                  onTap: _flipCamera,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildInstruction() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 170,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    widget.part.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _guideText(widget.part),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      height: 1.4,
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

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _capture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _capturing ? Colors.grey : Colors.white,
                    ),
                    child: _capturing
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('Starting camera...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  String _guideText(BodyPart part) {
    switch (part) {
      case BodyPart.tongue:
        return 'Stick your tongue out into the shape.\nUse even, natural light.';
      case BodyPart.palm:
        return 'Spread your palm inside the hand outline.\nFill the shape.';
      case BodyPart.nail:
        return 'Place four fingernails side by side.\nPress lightly to show color.';
      case BodyPart.eye:
        return 'Pull down your lower eyelid.\nExpose the pink conjunctiva.';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  GUIDE PAINTER — darkens everything except the guide shape
// ═══════════════════════════════════════════════════════════════

class _ImageGuidePainter extends CustomPainter {
  final ui.Image image;
  final Rect rect;

  _ImageGuidePainter({required this.image, required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    canvas.saveLayer(Offset.zero & size, Paint());

    // 1. Dark overlay
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    // 2. Punch hole with the PNG's alpha
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..filterQuality = FilterQuality.high,
    );

    canvas.restore();

    // 3. Draw outline in white using srcIn
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _ImageGuidePainter old) {
    return old.image != image || old.rect != rect;
  }
}
