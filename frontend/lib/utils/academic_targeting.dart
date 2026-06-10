import 'dart:convert';

import '../models/user.dart';

class AcademicTargeting {
  static String encodeTopicSegment(String? value) {
    if (value == null) return '';

    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    return base64UrlEncode(utf8.encode(trimmed)).replaceAll('=', '');
  }

  static String? buildScopedTopic({
    required String? faculty,
    required String? level,
    required String? field,
  }) {
    final sanitizedFaculty = encodeTopicSegment(faculty);
    final sanitizedLevel = encodeTopicSegment(level);
    final sanitizedField = encodeTopicSegment(field);

    if (sanitizedFaculty.isEmpty ||
        sanitizedLevel.isEmpty ||
        sanitizedField.isEmpty) {
      return null;
    }

    return 'faculte_${sanitizedFaculty}_niveau_${sanitizedLevel}_filiere_$sanitizedField';
  }

  static String? buildEventTopic({
    required bool isGlobal,
    required String? faculty,
    required String? level,
    required String? field,
  }) {
    if (isGlobal) return 'events_global';
    return buildScopedTopic(faculty: faculty, level: level, field: field);
  }

  static String? buildAdTopic({
    required bool isGlobal,
    required String? faculty,
    required String? level,
    required String? field,
  }) {
    if (isGlobal) return 'ads_global';
    return buildScopedTopic(faculty: faculty, level: level, field: field);
  }

  static List<String> buildUserTopics(UserModel user) {
    final topics = <String>{'events_global', 'ads_global'};

    final scopedTopic = buildScopedTopic(
      faculty: user.faculty,
      level: user.level,
      field: user.field,
    );
    if (scopedTopic != null) {
      topics.add(scopedTopic);
    }

    return topics.toList();
  }

  static bool matchesUser({
    required bool isGlobal,
    required String? faculty,
    required String? level,
    required String? field,
    required UserModel? user,
  }) {
    if (isGlobal) {
      return true;
    }
    if (user == null) {
      return false;
    }

    return _normalize(user.faculty) == _normalize(faculty) &&
        _normalize(user.level) == _normalize(level) &&
        _normalize(user.field) == _normalize(field);
  }

  static String audienceKey(UserModel? user) {
    if (user == null) return 'guest';

    return [
      user.id,
      _normalize(user.faculty),
      _normalize(user.level),
      _normalize(user.field),
    ].join('|');
  }

  static String describeAudience({
    required bool isGlobal,
    required String? faculty,
    required String? level,
    required String? field,
  }) {
    if (isGlobal) {
      return 'Globale';
    }

    final segments = <String>[
      if (_normalize(field).isNotEmpty) 'Filiere: ${_normalize(field)}',
      if (_normalize(level).isNotEmpty) 'Niveau: ${_normalize(level)}',
      if (_normalize(faculty).isNotEmpty) 'Faculte: ${_normalize(faculty)}',
    ];

    if (segments.isEmpty) {
      return 'Ciblage specifique';
    }

    return segments.join(' | ');
  }

  static String _normalize(String? value) => value?.trim() ?? '';
}
