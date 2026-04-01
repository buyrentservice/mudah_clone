import 'dart:io';
import 'dart:math';
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

class _FullImageViewState extends State<FullImageView> {
  late img.Image originalImage;
  late img.Image currentImage;
  Uint8List? displayBytes;

  final List<img.Image> undoStack = [];
  final List<img.Image> redoStack = [];

  // Rotation & ruler
  bool showRuler = false;
  double currentRotation = 0; // degrees (-180 to 180 range for display)
  double dragStartX = 0;
  double rotationStart = 0;
  double rotationVelocity = 0;
  final double friction = 0.95;

  @override
  void initState() {
    super.initState();
    _loadImage();
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
    _toggleRuler();
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

  void _toggleRuler() {
    setState(() {
      showRuler = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
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

  /// Returns a display-friendly rotation string (e.g., "-0.0°", "12.3°")
  String _getDisplayRotation() {
    double displayVal = currentRotation;
    // Normalize to -180..180 range for display
    if (displayVal > 180) {
      displayVal -= 360;
    }
    // Show sign for negative, but also show "-0.0" when exactly 0 or 360
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

          // Ruler container
          if (showRuler)
            Positioned(
              left: 0,
              right: 0,
              bottom: 80,
              child: _buildRulerWidget(),
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

  /// Builds the ruler widget matching the reference screenshot design:
  /// - Gray circle X (reset) button on left
  /// - Orange degree label on top center
  /// - Orange center indicator line
  /// - Gradient-opacity tick marks (dark center, fading to light edges)
  /// - 90-degree rotate button on right
  Widget _buildRulerWidget() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Degree label in orange
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _getDisplayRotation(),
              style: const TextStyle(
                color: Color(0xFFFF6D00),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Ruler row: X button, ruler ticks, 90 button
          SizedBox(
            height: 56,
            child: Row(
              children: [
                // X (reset) button - gray circle
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: GestureDetector(
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
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Ruler ticks area
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragStart: (details) {
                      dragStartX = details.localPosition.dx;
                      rotationStart = currentRotation;
                      rotationVelocity = 0;
                    },
                    onHorizontalDragUpdate: (details) {
                      final dx = details.localPosition.dx - dragStartX;
                      final deltaRotation = dx / 3;
                      setState(() {
                        currentRotation =
                            (rotationStart + deltaRotation) % 360;
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
                    child: ClipRect(
                      child: CustomPaint(
                        size: const Size(double.infinity, 56),
                        painter: GradientRulerPainter(currentRotation),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 90-degree rotate button
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: _rotate90,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.rotate_right,
                            color: Colors.grey.shade600,
                            size: 28,
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Text(
                              '90\u00B0',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
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

/// Custom painter for the ruler with gradient-opacity tick marks.
///
/// Design matches the reference screenshot:
/// - Shows a range of ~90 degrees centered on the current rotation
/// - Center indicator is a thick orange line with rounded caps
/// - Tick marks fade from dark (center) to light gray (edges)
/// - Major ticks (every 10°) are taller; minor ticks are shorter
class GradientRulerPainter extends CustomPainter {
  final double rotation;

  /// Visible range in degrees on each side of center
  static const double visibleRange = 45.0;

  /// Spacing between each degree tick in pixels
  static const double degreeSpacing = 6.0;

  GradientRulerPainter(this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final tickBottom = size.height - 4;

    // Draw center orange indicator line
    final centerPaint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, 8),
      Offset(centerX, tickBottom),
      centerPaint,
    );

    // Draw tick marks with gradient opacity
    final tickPaint = Paint()..strokeCap = StrokeCap.round;

    final int rangeInt = visibleRange.toInt();

    for (int i = -rangeInt; i <= rangeInt; i++) {
      if (i == 0) continue; // skip center (orange indicator is there)

      final double x = centerX + i * degreeSpacing;
      if (x < 0 || x > size.width) continue;

      // Calculate opacity: 1.0 at center, fading to 0.15 at edges
      final double distanceRatio = i.abs() / visibleRange;
      final double opacity = (1.0 - distanceRatio).clamp(0.15, 1.0);

      // Determine tick height based on degree value
      final int absDeg = ((rotation + i) % 360).abs().round();
      double tickHeight;
      double strokeWidth;

      if (absDeg % 10 == 0) {
        // Major tick every 10 degrees
        tickHeight = 22;
        strokeWidth = 2.0;
      } else if (absDeg % 5 == 0) {
        // Medium tick every 5 degrees
        tickHeight = 16;
        strokeWidth = 1.5;
      } else {
        // Minor tick every degree
        tickHeight = 10;
        strokeWidth = 1.2;
      }

      tickPaint.color = Color.fromRGBO(60, 60, 60, opacity);
      tickPaint.strokeWidth = strokeWidth;

      final tickTop = centerY + (tickBottom - centerY - tickHeight) / 2 +
          (tickHeight > 16 ? -2 : 2);
      canvas.drawLine(
        Offset(x, tickBottom - tickHeight),
        Offset(x, tickBottom),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GradientRulerPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
