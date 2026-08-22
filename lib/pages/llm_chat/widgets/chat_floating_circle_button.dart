import 'package:flutter/material.dart';

class ChatFloatingCircleButton extends StatelessWidget {
  final ColorScheme scheme;
  final IconData icon;
  final VoidCallback onTap;

  const ChatFloatingCircleButton({
    super.key,
    required this.scheme,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface.withValues(alpha: 0.9),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
