import 'package:flutter/material.dart';

/// Styles mutualisés des écrans d'authentification.
///
/// L'objectif est de retirer la duplication visuelle des champs
/// et de concentrer les ajustements UI dans un seul endroit.
class AuthFormTheme {
  static InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white),
      prefixIcon: Icon(icon, color: Colors.white),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Color.fromARGB(255, 255, 194, 190),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Color.fromARGB(255, 255, 200, 196),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      errorStyle: const TextStyle(
        color: Color.fromARGB(255, 255, 162, 155),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.1),
    );
  }
}
