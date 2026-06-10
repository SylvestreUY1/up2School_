// lib/widgets/custom_loading.dart
import 'package:flutter/material.dart';

class CustomLoading extends StatelessWidget {
  final Color? color;
  final double? size;
  
  const CustomLoading({
    super.key,
    this.color,
    this.size,
  });
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: color ?? const Color.fromARGB(255, 255, 255, 255), // Vert par défaut
        strokeWidth: size ?? 4.0,
      ),
    );
  }
}