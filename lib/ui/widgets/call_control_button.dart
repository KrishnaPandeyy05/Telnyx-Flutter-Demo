import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CallControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? activeColor;
  final double size;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
    this.size = 60,
  });

  @override
  State<CallControlButton> createState() => _CallControlButtonState();
}

class _CallControlButtonState extends State<CallControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.isActive
        ? (widget.activeColor ?? AppTheme.primaryTelnyx)
        : Colors.white.withOpacity(0.2);
        
    final iconColor = widget.isActive
        ? Colors.white
        : Colors.white.withOpacity(0.9);

    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Button circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: effectiveColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: widget.isActive ? 0 : 1,
                    ),
                    boxShadow: widget.isActive
                        ? [
                            BoxShadow(
                              color: effectiveColor.withOpacity(0.4),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.icon,
                    color: iconColor,
                    size: widget.size * 0.4,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Label
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
