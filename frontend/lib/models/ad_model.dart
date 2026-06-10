import 'package:cloud_firestore/cloud_firestore.dart';

class AdModel {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String targetUrl;
  final String faculty;
  final String level;
  final String field;
  final bool isGlobal;
  final bool isActive;
  final int clicks;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;

  AdModel({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.targetUrl,
    this.faculty = '',
    this.level = '',
    this.field = '',
    this.isGlobal = true,
    this.isActive = true,
    this.clicks = 0,
    this.startDate,
    this.endDate,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'targetUrl': targetUrl,
      'faculty': faculty,
      'level': level,
      'field': field,
      'isGlobal': isGlobal,
      'isActive': isActive,
      'clicks': clicks,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory AdModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is int) return value != 0;
      if (value is String) return value.toLowerCase() == 'true' || value == '1';
      return true;
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return AdModel(
      id: id.isNotEmpty ? id : (map['id']?.toString() ?? ''),
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      targetUrl: map['targetUrl'] ?? '',
      faculty: map['faculty']?.toString() ?? '',
      level: map['level']?.toString() ?? '',
      field: map['field']?.toString() ?? '',
      isGlobal: map.containsKey('isGlobal')
          ? parseBool(map['isGlobal'])
          : ((map['faculty']?.toString() ?? '').isEmpty &&
              (map['level']?.toString() ?? '').isEmpty &&
              (map['field']?.toString() ?? '').isEmpty),
      isActive: parseBool(map['isActive']),
      clicks: parseInt(map['clicks']),
      startDate: parseDate(map['startDate']),
      endDate: parseDate(map['endDate']),
      createdAt: parseDate(map['createdAt']),
    );
  }
}
