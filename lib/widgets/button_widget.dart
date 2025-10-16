import 'package:flutter/material.dart';

class ButtonWidget extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final bool isCompact;
  final bool isPrimary;
  final VoidCallback? onPressed; // Made nullable to support disabled state

  const ButtonWidget({
    super.key,
    this.text,
    this.icon,
    this.isCompact = false,
    this.isPrimary = true,
    required this.onPressed, // Still required, but can be null
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null;

    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return isPrimary
              ? const Color.fromARGB(255, 25, 25, 25).withOpacity(0.5)
              : Colors.white.withOpacity(0.5);
        }
        return isPrimary
            ? const Color.fromARGB(255, 25, 25, 25)
            : Colors.white;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.disabled)) {
          return (isPrimary ? Colors.white : Colors.black).withOpacity(0.5);
        }
        return isPrimary ? Colors.white : Colors.black;
      }),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.pressed)) {
          return isPrimary
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.1);
        }
        return null;
      }),
    );

    if (isCompact && icon != null) {
      return Container(
        decoration: BoxDecoration(
          color: isDisabled
              ? (isPrimary
              ? const Color.fromARGB(255, 25, 25, 25).withOpacity(0.5)
              : Colors.white.withOpacity(0.5))
              : (isPrimary
              ? const Color.fromARGB(255, 25, 25, 25)
              : Colors.white),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IconButton(
          icon: Icon(
            icon,
            color: isDisabled
                ? (isPrimary ? Colors.white : Colors.black).withOpacity(0.5)
                : (isPrimary ? Colors.white : Colors.black),
          ),
          onPressed: onPressed,
        ),
      );
    }

    return ElevatedButton(
      style: buttonStyle,
      onPressed: onPressed, // ElevatedButton handles null properly
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // Added to prevent button from expanding unnecessarily
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Icon(
                icon,
                color: isDisabled
                    ? (isPrimary ? Colors.white : Colors.black).withOpacity(0.5)
                    : (isPrimary ? Colors.white : Colors.black),
              ),
            ),
          Text(
            (text ?? 'Button').toUpperCase(),
            style: TextStyle(
              color: isDisabled
                  ? (isPrimary ? Colors.white : Colors.black).withOpacity(0.5)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}