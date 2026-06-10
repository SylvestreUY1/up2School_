// lib/widgets/file_filter_chip.dart - CORRIGÉ
import 'package:flutter/material.dart';
import '../utils/file_filters.dart';

class FileFilterChip extends StatelessWidget {
  final String label;
  final FileFilter filter;
  final FileFilter currentFilter;
  final Function(FileFilter) onSelected;
  final IconData? icon;
  
  const FileFilterChip({
    super.key,
    required this.label,
    required this.filter,
    required this.currentFilter,
    required this.onSelected,
    this.icon,
  });
  
  @override
  Widget build(BuildContext context) {
    final isSelected = currentFilter == filter;
    
    return FilterChip(
      label: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Text(label),
              ],
            )
          : Text(label),
      selected: isSelected,
      onSelected: (selected) => onSelected(filter),
      backgroundColor: isSelected
          ? const Color(0xFF307A59).withOpacity(0.1)
          : Colors.grey[200],
      selectedColor: const Color(0xFF307A59).withOpacity(0.2),
      checkmarkColor: const Color(0xFF307A59),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF307A59) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF307A59).withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
    );
  }
}