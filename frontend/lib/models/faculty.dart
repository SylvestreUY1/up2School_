class Faculty {
  String id;
  String name;
  List<String> levels;
  Map<String, List<String>> fields;
  Map<String, Map<String, List<String>>> units;
  Faculty({
    required this.id,
    required this.name,
    required this.levels,
    required this.fields,
    this.units = const {},
  });

  factory Faculty.fromMap(Map<dynamic, dynamic> map) {
    final data = Map<String, dynamic>.from(map);
    final rawFields = data['fields'];
    final rawUnits = data['units'];

    return Faculty(
      id: (data['id'] as String? ?? '').trim(),
      name: (data['name'] as String? ?? '').trim(),
      levels: _toTrimmedStringList(data['levels']),
      fields: _toFieldsMap(rawFields),
      units: _toUnitsMap(rawUnits),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'levels': levels,
      'fields': fields,
      'units': units,
    };
  }
}

List<String> _toTrimmedStringList(dynamic value) {
  if (value is! List) return const [];

  final result = <String>[];
  final seen = <String>{};

  for (final item in value) {
    final normalized = item.toString().trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    result.add(normalized);
  }

  return result;
}

Map<String, List<String>> _toFieldsMap(dynamic rawFields) {
  if (rawFields is! Map) return const {};

  final result = <String, List<String>>{};
  for (final entry in Map<String, dynamic>.from(rawFields).entries) {
    final level = entry.key.trim();
    if (level.isEmpty) continue;

    final values = _toTrimmedStringList(entry.value);
    result[level] = values;
  }

  return result;
}

Map<String, Map<String, List<String>>> _toUnitsMap(dynamic rawUnits) {
  if (rawUnits is! Map) return const {};

  final result = <String, Map<String, List<String>>>{};
  for (final entry in Map<String, dynamic>.from(rawUnits).entries) {
    final level = entry.key.trim();
    if (level.isEmpty || entry.value is! Map) continue;

    final fields = <String, List<String>>{};
    for (final fieldEntry in Map<String, dynamic>.from(entry.value).entries) {
      final field = fieldEntry.key.trim();
      if (field.isEmpty) continue;
      fields[field] = _toTrimmedStringList(fieldEntry.value);
    }
    result[level] = fields;
  }

  return result;
}

List<Faculty> sanitizeFaculties(List<Faculty> faculties) {
  final seenNames = <String>{};
  final result = <Faculty>[];

  for (final faculty in faculties) {
    final name = faculty.name.trim();
    if (name.isEmpty || !seenNames.add(name)) {
      continue;
    }

    result.add(
      Faculty(
        id: faculty.id.trim(),
        name: name,
        levels: _toTrimmedStringList(faculty.levels),
        fields: _toFieldsMap(faculty.fields),
        units: _toUnitsMap(faculty.units),
      ),
    );
  }

  return result;
}

List<Faculty> mergeFaculties(List<Faculty> primary, List<Faculty> fallback) {
  final mergedByName = <String, Faculty>{};

  void mergeOne(Faculty faculty) {
    final normalized = sanitizeFaculties([faculty]);
    if (normalized.isEmpty) return;

    final current = normalized.first;
    final existing = mergedByName[current.name];
    if (existing == null) {
      mergedByName[current.name] = current;
      return;
    }

    final levels = <String>[...existing.levels];
    for (final level in current.levels) {
      if (!levels.contains(level)) {
        levels.add(level);
      }
    }

    final fields = <String, List<String>>{};
    final allFieldLevels = <String>{
      ...existing.fields.keys,
      ...current.fields.keys,
    };
    for (final level in allFieldLevels) {
      final mergedFields = <String>[
        ...(existing.fields[level] ?? const []),
      ];
      for (final field in current.fields[level] ?? const []) {
        if (!mergedFields.contains(field)) {
          mergedFields.add(field);
        }
      }
      fields[level] = mergedFields;
    }

    final units = <String, Map<String, List<String>>>{};
    final allUnitLevels = <String>{
      ...existing.units.keys,
      ...current.units.keys,
    };
    for (final level in allUnitLevels) {
      final mergedFieldsForUnits = <String, List<String>>{};
      final existingLevelUnits = existing.units[level] ?? const {};
      final currentLevelUnits = current.units[level] ?? const {};
      final allUnitFields = <String>{
        ...existingLevelUnits.keys,
        ...currentLevelUnits.keys,
      };

      for (final field in allUnitFields) {
        final mergedUnits = <String>[
          ...(existingLevelUnits[field] ?? const []),
        ];
        for (final unit in currentLevelUnits[field] ?? const []) {
          if (!mergedUnits.contains(unit)) {
            mergedUnits.add(unit);
          }
        }
        mergedFieldsForUnits[field] = mergedUnits;
      }

      units[level] = mergedFieldsForUnits;
    }

    mergedByName[current.name] = Faculty(
      id: existing.id.isNotEmpty ? existing.id : current.id,
      name: current.name,
      levels: levels,
      fields: fields,
      units: units,
    );
  }

  for (final faculty in fallback) {
    mergeOne(faculty);
  }
  for (final faculty in primary) {
    mergeOne(faculty);
  }

  final merged = mergedByName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return sanitizeFaculties(merged);
}

class SelectionData {
  String faculty;
  String level;
  String field;
  String unit;
  String type;

  SelectionData({
    required this.faculty,
    required this.level,
    required this.field,
    required this.unit,
    required this.type,
  });
}
