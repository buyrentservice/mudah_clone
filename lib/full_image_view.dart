import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';

class FullImageView extends StatefulWidget {
  final File image;

  const FullImageView({super.key, required this.image});

  @override
  State<FullImageView> createState() => _FullImageViewState();
}

class _FullImageViewState extends State<FullImageView>
    with SingleTickerProviderStateMixin {
  late img.Image originalImage;
  late img.Image currentImage;
  Uint8List? displayBytes;

  final List<img.Image> undoStack = [];
  final List<img.Image> redoStack = [];

  // Rotation & ruler
  bool showRuler = false;
  double currentRotation = 0;
  double dragStartX = 0;
  double rotationStart = 0;
  double rotationVelocity = 0;
  final double friction = 0.95;

  // Ruler show/hide animation
  late AnimationController _rulerAnimController;
  late Animation<double> _rulerFadeAnim;
  late Animation<Offset> _rulerSlideAnim;

  @override
  void initState() {
    super.initState();
    _loadImage();

    _rulerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _rulerFadeAnim = CurvedAnimation(
      parent: _rulerAnimController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _rulerSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _rulerAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _rulerAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.image.readAsBytes();
    originalImage = img.decodeImage(bytes)!;
    currentImage = img.copyResize(originalImage, width: originalImage.width);
    _updateDisplay();
  }

  void _updateDisplay() {
    setState(() {
      displayBytes = Uint8List.fromList(img.encodeJpg(currentImage));
    });
  }

  void _pushToUndo() {
    undoStack.add(img.copyResize(currentImage, width: currentImage.width));
    redoStack.clear();
  }

  void _rotateCropperStyle({bool clockwise = true}) {
    _pushToUndo();
    currentRotation = (currentRotation + (clockwise ? 90 : -90)) % 360;
    if (currentRotation < 0) {
      currentRotation += 360;
    }
    currentImage = img.copyRotate(originalImage, angle: currentRotation);
    _updateDisplay();
    _showRuler();
  }

  void _rotate90() {
    _pushToUndo();
    currentRotation = (currentRotation + 90) % 360;
    currentImage = img.copyRotate(originalImage, angle: currentRotation);
    _updateDisplay();
  }

  void _flipHorizontal() {
    _pushToUndo();
    currentImage = img.flipHorizontal(currentImage);
    _updateDisplay();
  }

  void _flipVertical() {
    _pushToUndo();
    currentImage = img.flipVertical(currentImage);
    _updateDisplay();
  }

  void _undo() {
    if (undoStack.isNotEmpty) {
      redoStack.add(img.copyResize(currentImage, width: currentImage.width));
      currentImage = undoStack.removeLast();
      _updateDisplay();
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      undoStack.add(img.copyResize(currentImage, width: currentImage.width));
      currentImage = redoStack.removeLast();
      _updateDisplay();
    }
  }

  void _reset() {
    _pushToUndo();
    currentImage = img.copyResize(originalImage, width: originalImage.width);
    currentRotation = 0;
    _updateDisplay();
  }

  Future<void> _cropImage() async {
    _pushToUndo();
    final tempDir = Directory.systemTemp;
    final tempFile = await File(
      '${tempDir.path}/temp_crop.jpg',
    ).writeAsBytes(img.encodeJpg(currentImage));

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: tempFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Crop Image'),
      ],
    );

    if (croppedFile != null) {
      final bytes = await croppedFile.readAsBytes();
      currentImage = img.decodeImage(bytes)!;
      _updateDisplay();
    }
  }

  void _showRuler() {
    setState(() {
      showRuler = true;
    });
    _rulerAnimController.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && showRuler) {
        _hideRuler();
      }
    });
  }

  void _hideRuler() {
    _rulerAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          showRuler = false;
        });
      }
    });
  }

  void _startInertia() {
    if (rotationVelocity.abs() < 0.1) {
      return;
    }

    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 16));
      setState(() {
        currentRotation = (currentRotation + rotationVelocity) % 360;
        if (currentRotation < 0) {
          currentRotation += 360;
        }
        currentImage = img.copyRotate(originalImage, angle: currentRotation);
        _updateDisplay();
        rotationVelocity *= friction;
      });
      return rotationVelocity.abs() > 0.1;
    });
  }

  /// Display-friendly rotation string (e.g., "-0.0", "12.3")
  String _getDisplayRotation() {
    double displayVal = currentRotation;
    if (displayVal > 180) {
      displayVal -= 360;
    }
    if (displayVal.abs() < 0.05) {
      return '-0.0\u00B0';
    }
    return '${displayVal.toStringAsFixed(1)}\u00B0';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Edit Image', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Image
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 140),
              child: Center(
                child: displayBytes != null
                    ? InteractiveViewer(
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Image.memory(displayBytes!, fit: BoxFit.contain),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),

          // Ruler with slide + fade animation
          if (showRuler)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: SlideTransition(
                position: _rulerSlideAnim,
                child: FadeTransition(
                  opacity: _rulerFadeAnim,
                  child: _buildRulerCard(),
                ),
              ),
            ),

          // Toolbar icons
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildIconButtonWithLongPress(
                    Icons.rotate_right,
                    () => _rotateCropperStyle(clockwise: true),
                    () => _rotateCropperStyle(clockwise: false),
                  ),
                  _buildIconButton(Icons.flip, _flipHorizontal),
                  _buildIconButton(Icons.flip, _flipVertical),
                  _buildIconButton(Icons.crop, _cropImage),
                  _buildIconButton(Icons.undo, _undo),
                  _buildIconButton(Icons.redo, _redo),
                  _buildIconButton(Icons.restore, _reset),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pro ruler card with shadow, animations, and clean layout
  Widget _buildRulerCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Orange degree label
            Text(
              _getDisplayRotation(),
              style: const TextStyle(
                color: Color(0xFFFF6D00),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            // Row: X button | ruler ticks | 90 button
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: 8),
                  _buildCloseButton(),
                  const SizedBox(width: 6),
                  Expanded(child: _buildDraggableRuler()),
                  const SizedBox(width: 6),
                  _buildRotate90Button(),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gray circle close/reset button
  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          currentRotation = 0;
          currentImage = img.copyRotate(
            originalImage,
            angle: currentRotation,
          );
          _updateDisplay();
        });
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFB0B0B0),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.close_rounded,
            color: Colors.white,
            size: 16,
          ),
        ),
      ),
    );
  }

  /// Draggable ruler area with clipped custom paint
  Widget _buildDraggableRuler() {
    return GestureDetector(
      onHorizontalDragStart: (details) {
        dragStartX = details.localPosition.dx;
        rotationStart = currentRotation;
        rotationVelocity = 0;
      },
      onHorizontalDragUpdate: (details) {
        final dx = details.localPosition.dx - dragStartX;
        final deltaRotation = dx / 3;
        setState(() {
          currentRotation = (rotationStart + deltaRotation) % 360;
          if (currentRotation < 0) {
            currentRotation += 360;
          }
          currentImage = img.copyRotate(
            originalImage,
            angle: currentRotation,
          );
          _updateDisplay();
          rotationVelocity = details.delta.dx / 3;
        });
      },
      onHorizontalDragEnd: (details) {
        _startInertia();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          size: const Size(double.infinity, 44),
          painter: ProRulerPainter(currentRotation),
        ),
      ),
    );
  }

  /// 90-degree quick-rotate button
  Widget _buildRotate90Button() {
    return GestureDetector(
      onTap: _rotate90,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.rotate_right_rounded,
              color: Color(0xFF5A5A5A),
              size: 24,
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: const Text(
                  '90\u00B0',
                  style: TextStyle(
                    color: Color(0xFF5A5A5A),
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButtonWithLongPress(
    IconData icon,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}

/// Professional ruler painter with smooth gradient-opacity tick marks.
///
/// Matches iOS/Samsung photo editor style:
/// - +/-45 degree visible window centered on current rotation
/// - Orange pill-shaped center indicator with subtle glow
/// - Smooth cubic (smoothstep) opacity falloff from center to edges
/// - Major (10deg), medium (5deg), and minor (1deg) tick heights
/// - Vertically centered ticks for a clean, balanced look
class ProRulerPainter extends CustomPainter {
  final double rotation;

  static const double _visibleRange = 45.0;
  static const double _tickSpacing = 6.0;

  ProRulerPainter(this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // --- Orange center indicator (pill with glow) ---
    const indicatorWidth = 3.6;
    const indicatorHeight = 32.0;
    final indicatorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, centerY + 2),
        width: indicatorWidth,
        height: indicatorHeight,
      ),
      const Radius.circular(2.0),
    );

    // Soft glow behind indicator
    canvas.drawRRect(
      indicatorRect.inflate(2.0),
      Paint()
        ..color = const Color(0xFFFF6D00).withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Solid indicator
    canvas.drawRRect(
      indicatorRect,
      Paint()..color = const Color(0xFFFF6D00),
    );

    // --- Tick marks with smooth gradient ---
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    final int range = _visibleRange.toInt();

    for (int i = -range; i <= range; i++) {
      if (i == 0) continue;

      final double x = centerX + i * _tickSpacing;
      if (x < 0 || x > size.width) continue;

      // Smooth cubic falloff (smoothstep)
      final double t = i.abs() / _visibleRange;
      final double opacity = _smoothStep(1.0 - t).clamp(0.06, 1.0);

      // Tick height & width based on degree position
      final int degreeValue = ((rotation + i) % 360).round();
      final bool isMajor = degreeValue % 10 == 0;
      final bool isMedium = degreeValue % 5 == 0;

      double tickH;
      double strokeW;

      if (isMajor) {
        tickH = 20;
        strokeW = 1.8;
      } else if (isMedium) {
        tickH = 14;
        strokeW = 1.3;
      } else {
        tickH = 9;
        strokeW = 1.0;
      }

      // Vertically center ticks, shifted slightly down
      final tickMidY = centerY + 2;

      final int alpha = (opacity * 230).round().clamp(0, 255);
      tickPaint
        ..color = Color.fromARGB(alpha, 45, 45, 45)
        ..strokeWidth = strokeW;

      canvas.drawLine(
        Offset(x, tickMidY - tickH / 2),
        Offset(x, tickMidY + tickH / 2),
        tickPaint,
      );
    }
  }

  /// Hermite smoothstep for natural opacity falloff
  double _smoothStep(double x) {
    final c = x.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  bool shouldRepaint(covariant ProRulerPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
