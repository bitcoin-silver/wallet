import 'package:flutter/material.dart';

class ButtonWidget extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final bool isCompact;
  final bool isPrimary;
  final VoidCallback onPressed;

  const ButtonWidget({
    super.key,
    this.text,
    this.icon,
    this.isCompact = false,
    this.isPrimary = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.all(
        isPrimary ? const Color.fromARGB(255, 25, 25, 25) : Colors.white,
      ),
      foregroundColor: WidgetStateProperty.all(
        isPrimary ? Colors.white : Colors.black,
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    if (isCompact && icon != null) {
      return Container(
        decoration: BoxDecoration(
          color:
              isPrimary ? const Color.fromARGB(255, 25, 25, 25) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(icon, color: isPrimary ? Colors.white : Colors.black),
          onPressed: onPressed,
        ),
      );
    }

    return ElevatedButton(
      style: buttonStyle,
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(icon, color: isPrimary ? Colors.white : Colors.black),
            ),
          Text(
            (text ?? 'Button').toUpperCase(),
          ),
        ],
      ),
    );
  }
}
