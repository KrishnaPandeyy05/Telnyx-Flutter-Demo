import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AudioWaveformWidget extends StatefulWidget {
  final int barCount;
  final double maxHeight;
  final Color? barColor;
  final bool isAnimating;

  const AudioWaveformWidget({
    super.key,
    this.barCount = 20,
    this.maxHeight = 60,
    this.barColor,
    this.isAnimating = true,
  });

  @override
  State<AudioWaveformWidget> createState() => _AudioWaveformWidgetState();
}

class _AudioWaveformWidgetState extends State<AudioWaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  final Random _random = Random();
  List<double> _barHeights = [];

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_animationController);
    
    // Initialize bar heights
    _generateBarHeights();
    
    if (widget.isAnimating) {
      _startAnimation();
    }
    
    _animation.addListener(() {
      setState(() {
        _generateBarHeights();
      });
    });
  }

  void _startAnimation() {
    _animationController.repeat();
  }

  void _generateBarHeights() {
    _barHeights = List.generate(widget.barCount, (index) {
      // Create more realistic waveform pattern
      final baseHeight = widget.maxHeight * 0.1;
      final variableHeight = widget.maxHeight * 0.9;
      
      // Simulate audio levels with some bars being taller (voice activity)
      double multiplier;
      if (_random.nextDouble() > 0.7) {
        // High activity (voice)
        multiplier = 0.6 + _random.nextDouble() * 0.4;
      } else if (_random.nextDouble() > 0.4) {
        // Medium activity
        multiplier = 0.3 + _random.nextDouble() * 0.3;
      } else {
        // Low activity
        multiplier = _random.nextDouble() * 0.3;
      }
      
      return baseHeight + (variableHeight * multiplier);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBarColor = widget.barColor ?? Colors.white.withOpacity(0.6);
    
    return Container(
      height: widget.maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: _barHeights.isNotEmpty 
                ? _barHeights[index] 
                : widget.maxHeight * 0.1,
            decoration: BoxDecoration(
              color: effectiveBarColor,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: effectiveBarColor.withOpacity(0.3),
                  blurRadius: 2,
                  spreadRadius: 0.5,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// Static waveform for design purposes
class StaticWaveformWidget extends StatelessWidget {
  final int barCount;
  final double maxHeight;
  final Color? barColor;
  final List<double>? customHeights;

  const StaticWaveformWidget({
    super.key,
    this.barCount = 15,
    this.maxHeight = 40,
    this.barColor,
    this.customHeights,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBarColor = barColor ?? AppTheme.primaryTelnyx.withOpacity(0.7);
    
    // Predefined pattern for consistent design
    final heights = customHeights ?? [
      0.2, 0.8, 0.3, 0.9, 0.1, 0.6, 0.4, 1.0, 0.7, 0.3,
      0.5, 0.9, 0.2, 0.6, 0.8
    ].take(barCount).toList();
    
    return Container(
      height: maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(barCount, (index) {
          final normalizedIndex = index % heights.length;
          return Container(
            width: 3,
            height: maxHeight * heights[normalizedIndex],
            decoration: BoxDecoration(
              color: effectiveBarColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
