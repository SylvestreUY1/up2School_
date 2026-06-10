import 'package:hive/hive.dart';
import '../utils/document_types.dart';

part 'file.g.dart';

@HiveType(typeId: 0)
class FileModel {
  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String url;
  @HiveField(3)
  String fileName;
  @HiveField(4)
  String fileType;
  @HiveField(5)
  String faculty;
  @HiveField(6)
  String level;
  @HiveField(7)
  String field;
  @HiveField(8)
  String unit;
  @HiveField(9)
  String type;
  @HiveField(10)
  int? size;
  @HiveField(11)
  DateTime uploadedAt;
  @HiveField(12)
  String uploadedBy;
  @HiveField(13)
  List<String> favorites;
  @HiveField(14)
  List<String> viewedBy;
  @HiveField(15)
  int downloadCount;
  @HiveField(16)
  int viewCount;
  @HiveField(17)
  Map<String, double> readingProgress;
  @HiveField(18)
  DateTime? lastOpened;
  @HiveField(19)
  String? localPath;
  DateTime? publishDate;
  bool canAccess;
  bool isOldFile;
  bool isPremiumLocked;
  String? accessDeniedReason;
  String? currentSchoolYearStart;
  String? storagePath;

  FileModel({
    required this.id,
    required this.name,
    required this.url,
    required this.fileName,
    required this.fileType,
    required this.faculty,
    required this.level,
    required this.field,
    required this.unit,
    required this.type,
    required this.uploadedAt,
    required this.uploadedBy,
    this.favorites = const [],
    this.downloadCount = 0,
    this.viewCount = 0,
    this.readingProgress = const {},
    this.lastOpened,
    this.localPath,
    this.size,
    this.viewedBy = const [],
    this.publishDate,
    this.canAccess = true,
    this.isOldFile = false,
    this.isPremiumLocked = false,
    this.accessDeniedReason,
    this.currentSchoolYearStart,
    this.storagePath,
  });

  factory FileModel.fromMap(Map<String, dynamic> map) {
    final uploadedAt = DateTime.parse(map['uploadedAt']);
    return FileModel(
      id: map['id'],
      name: map['name'],
      url: map['url'] ?? '',
      fileName: map['fileName'],
      fileType: map['fileType'],
      faculty: map['faculty'],
      level: map['level'],
      field: map['field'],
      unit: map['unit'] ?? '',
      type: normalizeDocumentType(map['type']?.toString()),
      size: _asInt(map['size']),
      uploadedAt: uploadedAt,
      uploadedBy: map['uploadedBy'],
      favorites: List<String>.from(map['favorites'] ?? []),
      downloadCount: _asInt(map['downloadCount']) ?? 0,
      viewCount: _asInt(map['viewCount']) ?? 0,
      readingProgress: _asReadingProgressMap(map['readingProgress']),
      lastOpened:
          map['lastOpened'] != null ? DateTime.parse(map['lastOpened']) : null,
      localPath: map['localPath'],
      viewedBy: List<String>.from(map['viewedBy'] ?? []),
      publishDate: map['publishDate'] != null
          ? DateTime.tryParse(map['publishDate'])
          : uploadedAt,
      canAccess: map['canAccess'] != false,
      isOldFile: map['isOldFile'] == true,
      isPremiumLocked: map['isPremiumLocked'] == true,
      accessDeniedReason: map['accessDeniedReason'],
      currentSchoolYearStart: map['currentSchoolYearStart'],
      storagePath: map['storagePath'],
    );
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString());
  }

  static Map<String, double> _asReadingProgressMap(dynamic raw) {
    if (raw is! Map) return const {};

    final result = <String, double>{};
    for (final entry in Map<dynamic, dynamic>.from(raw).entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (value is num) {
        result[key] = value.toDouble();
        continue;
      }

      final parsed = double.tryParse(value.toString());
      if (parsed != null) {
        result[key] = parsed;
      }
    }

    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'fileName': fileName,
      'fileType': fileType,
      'faculty': faculty,
      'level': level,
      'field': field,
      'unit': unit,
      'type': normalizeDocumentType(type),
      'uploadedAt': uploadedAt.toIso8601String(),
      'publishDate': (publishDate ?? uploadedAt).toIso8601String(),
      'uploadedBy': uploadedBy,
      'favorites': favorites,
      'downloadCount': downloadCount,
      'viewCount': viewCount,
      'readingProgress': readingProgress,
      'lastOpened': lastOpened?.toIso8601String(),
      'localPath': localPath,
      'canAccess': canAccess,
      'isOldFile': isOldFile,
      'isPremiumLocked': isPremiumLocked,
      'accessDeniedReason': accessDeniedReason,
      'currentSchoolYearStart': currentSchoolYearStart,
      'storagePath': storagePath,
      if (size != null) 'size': size,
    };
  }

  FileModel copyWith({
    String? id,
    String? name,
    String? url,
    String? fileName,
    String? fileType,
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
    int? size,
    DateTime? uploadedAt,
    String? uploadedBy,
    List<String>? favorites,
    List<String>? viewedBy,
    int? downloadCount,
    int? viewCount,
    Map<String, double>? readingProgress,
    DateTime? lastOpened,
    String? localPath,
    DateTime? publishDate,
    bool? canAccess,
    bool? isOldFile,
    bool? isPremiumLocked,
    String? accessDeniedReason,
    String? currentSchoolYearStart,
    String? storagePath,
  }) {
    return FileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      faculty: faculty ?? this.faculty,
      level: level ?? this.level,
      field: field ?? this.field,
      unit: unit ?? this.unit,
      type: type ?? this.type,
      size: size ?? this.size,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      favorites: favorites ?? this.favorites,
      viewedBy: viewedBy ?? this.viewedBy,
      downloadCount: downloadCount ?? this.downloadCount,
      viewCount: viewCount ?? this.viewCount,
      readingProgress: readingProgress ?? this.readingProgress,
      lastOpened: lastOpened ?? this.lastOpened,
      localPath: localPath ?? this.localPath,
      publishDate: publishDate ?? this.publishDate,
      canAccess: canAccess ?? this.canAccess,
      isOldFile: isOldFile ?? this.isOldFile,
      isPremiumLocked: isPremiumLocked ?? this.isPremiumLocked,
      accessDeniedReason: accessDeniedReason ?? this.accessDeniedReason,
      currentSchoolYearStart:
          currentSchoolYearStart ?? this.currentSchoolYearStart,
      storagePath: storagePath ?? this.storagePath,
    );
  }

  void updateReadingProgress(String userId, double progress) {
    readingProgress[userId] = progress;
  }

  void incrementViewCount() {
    viewCount++;
  }

  void markAsOpened(String userId) {
    lastOpened = DateTime.now();
  }
}
