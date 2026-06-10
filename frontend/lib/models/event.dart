import 'dart:convert';

class Event {
  String id;
  String title;
  String description;
  DateTime date;
  String location;
  String faculty;
  String level;
  String field;
  String createdBy;
  DateTime createdAt;
  List<String> imageUrls;
  bool isGlobal;
  bool reminder48hSent;
  bool reminder12hSent;
  bool reminder1hSent;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.location,
    required this.faculty,
    required this.level,
    required this.field,
    required this.createdBy,
    required this.createdAt,
    this.imageUrls = const [],
    this.isGlobal = false,
    this.reminder48hSent = false,
    this.reminder12hSent = false,
    this.reminder1hSent = false,
  });

  static DateTime _parseDate(dynamic value, DateTime fallback) {
    if (value == null) return fallback;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? fallback;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map && value.containsKey('_seconds')) {
      final seconds = value['_seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      }
    }
    return fallback;
  }

  static bool _parseBool(dynamic value) {
    return value == true || value == 1 || value == '1' || value == 'true';
  }

  static List<String> _parseImageUrls(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toList();
        }
      } catch (_) {
        return const <String>[];
      }
    }

    return const <String>[];
  }

  factory Event.fromMap(Map<dynamic, dynamic> map) {
    final data = Map<String, dynamic>.from(map);
    final now = DateTime.now();

    return Event(
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      date: _parseDate(data['date'], now),
      location: data['location']?.toString() ?? '',
      faculty: data['faculty']?.toString() ?? '',
      level: data['level']?.toString() ?? '',
      field: data['field']?.toString() ?? '',
      createdBy: data['createdBy']?.toString() ?? '',
      createdAt: _parseDate(data['createdAt'], now),
      imageUrls: _parseImageUrls(data['imageUrls']),
      isGlobal: _parseBool(data['isGlobal']),
      reminder48hSent: _parseBool(data['reminder48hSent']),
      reminder12hSent: _parseBool(data['reminder12hSent']),
      reminder1hSent: _parseBool(data['reminder1hSent']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'location': location,
      'faculty': faculty,
      'level': level,
      'field': field,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'imageUrls': imageUrls,
      'isGlobal': isGlobal,
      'reminder48hSent': reminder48hSent,
      'reminder12hSent': reminder12hSent,
      'reminder1hSent': reminder1hSent,
    };
  }
}
