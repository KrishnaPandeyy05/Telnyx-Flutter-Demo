import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    
    return SizedBox(
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
