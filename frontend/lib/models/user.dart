// lib/models/user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String email;
  final String? name;
  final String? phone;
  final UserRole role;
  final String? faculty;
  final String? level;
  final String? field;
  final DateTime createdAt;
  final DateTime? lastActivity;
  final bool subscribed;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final String? subscriptionSchoolYear;
  final String? lastSubscriptionTransactionId;
  final bool hasActiveSubscription;

  UserModel({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.role = UserRole.student,
    this.faculty,
    this.level,
    this.field,
    required this.createdAt,
    this.lastActivity,
    this.subscribed = false,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.subscriptionSchoolYear,
    this.lastSubscriptionTransactionId,
    this.hasActiveSubscription = false,
  });

  static DateTime? _parseFlexibleDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is Map && value.containsKey('_seconds')) {
      return DateTime.fromMillisecondsSinceEpoch(value['_seconds'] * 1000);
    }
    if (value is Timestamp) return value.toDate();
    return null;
  }

  // Méthode factory pour créer un UserModel depuis Map (pour Firestore)
  factory UserModel.fromMap(Map<String, dynamic> map) {
    final subscriptionEndDate = _parseFlexibleDate(map['subscriptionEndDate']);
    final hasActiveSubscription = map['hasActiveSubscription'] == true ||
        ((map['subscribed'] == true) &&
            subscriptionEndDate != null &&
            subscriptionEndDate.isAfter(DateTime.now()));

    return UserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'],
      phone: map['phone'],
      role: _parseUserRole(map['role'] ?? 'student'),
      faculty: map['faculty'],
      level: map['level'],
      field: map['field'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      lastActivity: _parseFlexibleDate(map['lastActivity']),
      subscribed: map['subscribed'] == true || hasActiveSubscription,
      subscriptionStartDate: _parseFlexibleDate(map['subscriptionStartDate']),
      subscriptionEndDate: subscriptionEndDate,
      subscriptionSchoolYear: map['subscriptionSchoolYear'],
      lastSubscriptionTransactionId: map['lastSubscriptionTransactionId'],
      hasActiveSubscription: hasActiveSubscription,
    );
  }

  // Méthode factory pour créer un UserModel depuis JSON (pour SharedPreferences)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'],
      phone: json['phone'],
      role: UserRole.values[json['role'] ?? 1], // Utilise l'index de l'enum
      faculty: json['faculty'],
      level: json['level'],
      field: json['field'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      lastActivity: json['lastActivity'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastActivity'])
          : null,
      subscribed: json['subscribed'] == true,
      subscriptionStartDate: json['subscriptionStartDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['subscriptionStartDate'])
          : null,
      subscriptionEndDate: json['subscriptionEndDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['subscriptionEndDate'])
          : null,
      subscriptionSchoolYear: json['subscriptionSchoolYear'],
      lastSubscriptionTransactionId: json['lastSubscriptionTransactionId'],
      hasActiveSubscription: json['hasActiveSubscription'] == true,
    );
  }

  // Méthode pour convertir en Map (pour Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'role': role.toString().split('.').last,
      'faculty': faculty,
      'level': level,
      'field': field,
      'createdAt': createdAt.toIso8601String(),
      if (lastActivity != null) 'lastActivity': lastActivity!.toIso8601String(),
      'subscribed': subscribed,
      if (subscriptionStartDate != null)
        'subscriptionStartDate': subscriptionStartDate!.toIso8601String(),
      if (subscriptionEndDate != null)
        'subscriptionEndDate': subscriptionEndDate!.toIso8601String(),
      if (subscriptionSchoolYear != null)
        'subscriptionSchoolYear': subscriptionSchoolYear,
      if (lastSubscriptionTransactionId != null)
        'lastSubscriptionTransactionId': lastSubscriptionTransactionId,
      'hasActiveSubscription': hasActiveSubscription,
    };
  }

  // Méthode pour convertir en JSON (pour SharedPreferences)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'role': role.index, // Sauvegarde l'index de l'enum
      'faculty': faculty,
      'level': level,
      'field': field,
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (lastActivity != null)
        'lastActivity': lastActivity!.millisecondsSinceEpoch,
      'subscribed': subscribed,
      if (subscriptionStartDate != null)
        'subscriptionStartDate': subscriptionStartDate!.millisecondsSinceEpoch,
      if (subscriptionEndDate != null)
        'subscriptionEndDate': subscriptionEndDate!.millisecondsSinceEpoch,
      if (subscriptionSchoolYear != null)
        'subscriptionSchoolYear': subscriptionSchoolYear,
      if (lastSubscriptionTransactionId != null)
        'lastSubscriptionTransactionId': lastSubscriptionTransactionId,
      'hasActiveSubscription': hasActiveSubscription,
    };
  }

  // Méthode pour créer une copie avec des valeurs modifiées
  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    UserRole? role,
    String? faculty,
    String? level,
    String? field,
    DateTime? createdAt,
    DateTime? lastActivity,
    bool? subscribed,
    DateTime? subscriptionStartDate,
    DateTime? subscriptionEndDate,
    String? subscriptionSchoolYear,
    String? lastSubscriptionTransactionId,
    bool? hasActiveSubscription,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      faculty: faculty ?? this.faculty,
      level: level ?? this.level,
      field: field ?? this.field,
      createdAt: createdAt ?? this.createdAt,
      lastActivity: lastActivity ?? this.lastActivity,
      subscribed: subscribed ?? this.subscribed,
      subscriptionStartDate:
          subscriptionStartDate ?? this.subscriptionStartDate,
      subscriptionEndDate: subscriptionEndDate ?? this.subscriptionEndDate,
      subscriptionSchoolYear:
          subscriptionSchoolYear ?? this.subscriptionSchoolYear,
      lastSubscriptionTransactionId:
          lastSubscriptionTransactionId ?? this.lastSubscriptionTransactionId,
      hasActiveSubscription:
          hasActiveSubscription ?? this.hasActiveSubscription,
    );
  }

  bool get isSubscriptionActive =>
      hasActiveSubscription ||
      (subscribed &&
          subscriptionEndDate != null &&
          subscriptionEndDate!.isAfter(DateTime.now()));

  // Méthode utilitaire pour parser le rôle utilisateur depuis une chaîne
  static UserRole _parseUserRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'delegate':
        return UserRole.delegate;
      case 'student':
        return UserRole.student;
      case 'guest':
        return UserRole.guest;
      default:
        return UserRole.student;
    }
  }

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, name: $name, role: $role)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id && other.email == email;
  }

  @override
  int get hashCode => id.hashCode ^ email.hashCode;
}

enum UserRole {
  guest,
  student,
  delegate,
  admin;

  String get label {
    switch (this) {
      case UserRole.guest:
        return 'Invité';
      case UserRole.student:
        return 'Étudiant';
      case UserRole.delegate:
        return 'Délégué';
      case UserRole.admin:
        return 'Administrateur';
    }
  }
}
