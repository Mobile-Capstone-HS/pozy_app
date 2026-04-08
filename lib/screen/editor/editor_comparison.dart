import 'dart:typed_data';

import 'package:flutter/material.dart';

class ComparisonView extends StatefulWidget {
  final Uint8List originalBytes;
  final Uint8List editedBytes;
  final double width;
  final double height;

  const ComparisonView({
    super.key,
    required this.originalBytes,
    required this.editedBytes,
    required this.width,
    required this.height,
  });

  @override
  State<ComparisonView> createState() => _ComparisonViewState();
}

class _ComparisonViewState extends State<ComparisonView> {
  double _dividerFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    final dividerX = widget.width * _dividerFraction;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            widget.editedBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
          ClipRect(
            clipper: _LeftClipper(dividerX),
            child: Image.memory(
              widget.originalBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: _ComparisonLabel(text: '원본'),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _ComparisonLabel(text: '편집'),
          ),
          Positioned(
            left: dividerX - 16,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dividerFraction += details.delta.dx / widget.width;
                  _dividerFraction = _dividerFraction.clamp(0.05, 0.95);
                });
              },
              child: Container(
                width: 32,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 2,
                      height: widget.height * 0.35,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.compare_arrows,
                        size: 16,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 2,
                      height: widget.height * 0.35,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double dividerX;

  _LeftClipper(this.dividerX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, dividerX, size.height);
  }

  @override
  bool shouldReclip(_LeftClipper oldClipper) {
    return oldClipper.dividerX != dividerX;
  }
}

class _ComparisonLabel extends StatelessWidget {
  final String text;

  const _ComparisonLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
