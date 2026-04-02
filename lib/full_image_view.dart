import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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

  // Crop state
  bool isCropped = false;
  double cropBoxSize = 0;
  Offset cropBoxCenter = Offset.zero;

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
    isCropped = false;
    _updateDisplay();
    _showRuler();
  }

  void _rotate90() {
    _pushToUndo();
    currentRotation = (currentRotation + 90) % 360;
    currentImage = img.copyRotate(originalImage, angle: currentRotation);
    isCropped = false;
    _updateDisplay();
  }

  void _flipHorizontal() {
    _pushToUndo();
    currentImage = img.flipHorizontal(currentImage);
    isCropped = false;
    _updateDisplay();
  }

  void _flipVertical() {
    _pushToUndo();
    currentImage = img.flipVertical(currentImage);
    isCropped = false;
    _updateDisplay();
  }

  void _undo() {
    if (undoStack.isNotEmpty) {
      redoStack.add(img.copyResize(currentImage, width: currentImage.width));
      currentImage = undoStack.removeLast();
      isCropped = false;
      _updateDisplay();
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      undoStack.add(img.copyResize(currentImage, width: currentImage.width));
      currentImage = redoStack.removeLast();
      isCropped = false;
      _updateDisplay();
    }
  }

  void _reset() {
    _pushToUndo();
    currentImage = img.copyResize(originalImage, width: originalImage.width);
    currentRotation = 0;
    isCropped = false;
    _updateDisplay();
  }

  void _cropImage() {
    if (displayBytes == null) return;

    final screenSize = MediaQuery.of(context).size;
    cropBoxSize =
        (screenSize.width < screenSize.height
            ? screenSize.width
            : screenSize.height) *
        0.6;
    cropBoxCenter = Offset(screenSize.width / 2, screenSize.height / 2);

    final imgRatio = currentImage.width / currentImage.height;
    double displayWidth = screenSize.width;
    double displayHeight = screenSize.height;
    if (screenSize.width / screenSize.height > imgRatio) {
      displayWidth = screenSize.height * imgRatio;
    } else {
      displayHeight = screenSize.width / imgRatio;
    }

    final offsetX = (screenSize.width - displayWidth) / 2;
    final offsetY = (screenSize.height - displayHeight) / 2;

    final cropLeft =
        ((cropBoxCenter.dx - cropBoxSize / 2 - offsetX) /
                displayWidth *
                currentImage.width)
            .round()
            .clamp(0, currentImage.width - 1);
    final cropTop =
        ((cropBoxCenter.dy - cropBoxSize / 2 - offsetY) /
                displayHeight *
                currentImage.height)
            .round()
            .clamp(0, currentImage.height - 1);
    final cropW = (cropBoxSize / displayWidth * currentImage.width)
        .round()
        .clamp(1, currentImage.width - cropLeft);
    final cropH = (cropBoxSize / displayHeight * currentImage.height)
        .round()
        .clamp(1, currentImage.height - cropTop);

    _pushToUndo();
    currentImage = img.copyCrop(
      currentImage,
      x: cropLeft,
      y: cropTop,
      width: cropW,
      height: cropH,
    );

    // Reset rotation to 0 because the rotation is already baked into the
    // pixel data via img.copyRotate. Without this, Transform.rotate would
    // apply the rotation a second time, causing the cropped image to appear
    // rotated inside the red dotted box.
    currentRotation = 0;

    _updateDisplay();
    isCropped = true;
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
    final maxWidth = MediaQuery.of(context).size.width;
    final maxHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Edit Image', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (showRuler) _hideRuler();
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Image display
            if (displayBytes != null)
              Center(
                child: isCropped
                    ? SizedBox(
                        width: cropBoxSize,
                        height: cropBoxSize,
                        child: Image.memory(displayBytes!, fit: BoxFit.fill),
                      )
                    : InteractiveViewer(
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 0.05,
                        maxScale: 4.0,
                        boundaryMargin: const EdgeInsets.all(1000),
                        child: Image.memory(
                          displayBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Red dotted overlay (hidden after crop)
            if (!isCropped)
              IgnorePointer(
                child: Center(
                  child: CustomPaint(
                    size: Size(maxWidth, maxHeight),
                    painter: FixedOverlayPainter(),
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

            // Bottom toolbar
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
                    _buildIconButton(Icons.flip, () {
                      _flipHorizontal();
                      _hideRuler();
                    }),
                    _buildIconButton(Icons.flip, () {
                      _flipVertical();
                      _hideRuler();
                    }, rotateIcon: true),
                    _buildIconButton(Icons.crop, () {
                      _cropImage();
                      _hideRuler();
                    }),
                    _buildIconButton(Icons.undo, () {
                      _undo();
                      _hideRuler();
                    }),
                    _buildIconButton(Icons.redo, () {
                      _redo();
                      _hideRuler();
                    }),
                    _buildIconButton(Icons.restore, () {
                      _reset();
                      _hideRuler();
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
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
          isCropped = false;
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
          isCropped = false;
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

  Widget _buildIconButton(
    IconData icon,
    VoidCallback onTap, {
    bool rotateIcon = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: rotateIcon
          ? Transform.rotate(
              angle: 3.1415927 / 2,
              child: Icon(icon, color: Colors.white, size: 28),
            )
          : Icon(icon, color: Colors.white, size: 28),
    );
  }
}

/// Fixed red dotted overlay painter - draws a semi-transparent overlay with a
/// clear rectangular cutout bordered by a red dashed line.
class FixedOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color.fromRGBO(0, 0, 0, 0.5);

    final boxSize =
        (size.width < size.height ? size.width : size.height) * 0.6;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: boxSize,
      height: boxSize,
    );

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRect(rect, clearPaint);
    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const double dashWidth = 6.0;
    const double dashSpace = 4.0;

    // Top edge
    double startX = rect.left;
    while (startX < rect.right) {
      final endX = (startX + dashWidth).clamp(rect.left, rect.right);
      canvas.drawLine(
        Offset(startX, rect.top),
        Offset(endX, rect.top),
        borderPaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Right edge
    double startY = rect.top;
    while (startY < rect.bottom) {
      final endY = (startY + dashWidth).clamp(rect.top, rect.bottom);
      canvas.drawLine(
        Offset(rect.right, startY),
        Offset(rect.right, endY),
        borderPaint,
      );
      startY += dashWidth + dashSpace;
    }

    // Bottom edge
    startX = rect.left;
    while (startX < rect.right) {
      final endX = (startX + dashWidth).clamp(rect.left, rect.right);
      canvas.drawLine(
        Offset(startX, rect.bottom),
        Offset(endX, rect.bottom),
        borderPaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Left edge
    startY = rect.top;
    while (startY < rect.bottom) {
      final endY = (startY + dashWidth).clamp(rect.top, rect.bottom);
      canvas.drawLine(
        Offset(rect.left, startY),
        Offset(rect.left, endY),
        borderPaint,
      );
      startY += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
