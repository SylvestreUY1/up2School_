import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/event.dart';

class LocalEventStorage {
  static const Duration _recentPastRetention = Duration(days: 1);
  static final LocalEventStorage _instance = LocalEventStorage._internal();
  factory LocalEventStorage() => _instance;
  LocalEventStorage._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'events.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE events (
            id TEXT PRIMARY KEY,
            title TEXT,
            description TEXT,
            date TEXT,
            location TEXT,
            faculty TEXT,
            level TEXT,
            field TEXT,
            createdBy TEXT,
            createdAt TEXT,
            imageUrls TEXT,
            isGlobal INTEGER,
            reminder48hSent INTEGER,
            reminder12hSent INTEGER,
            reminder1hSent INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE events ADD COLUMN createdBy TEXT DEFAULT \'\'',
          );
          await db.execute(
            'ALTER TABLE events ADD COLUMN createdAt TEXT DEFAULT \'\'',
          );
          await db.execute(
            'ALTER TABLE events ADD COLUMN imageUrls TEXT DEFAULT \'[]\'',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE events ADD COLUMN reminder1hSent INTEGER DEFAULT 0',
          );
        }
      },
    );
  }

  Future<void> insertEvent(Event event) async {
    final db = await this.db;
    final existing = await db.query(
      'events',
      columns: ['reminder48hSent', 'reminder12hSent', 'reminder1hSent'],
      where: 'id = ?',
      whereArgs: [event.id],
      limit: 1,
    );

    final existingReminder48hSent = existing.isNotEmpty
        ? (existing.first['reminder48hSent'] as int? ?? 0) == 1
        : false;
    final existingReminder12hSent = existing.isNotEmpty
        ? (existing.first['reminder12hSent'] as int? ?? 0) == 1
        : false;
    final existingReminder1hSent = existing.isNotEmpty
        ? (existing.first['reminder1hSent'] as int? ?? 0) == 1
        : false;

    await db.insert(
      'events',
      {
        'id': event.id,
        'title': event.title,
        'description': event.description,
        'date': event.date.toIso8601String(),
        'location': event.location,
        'faculty': event.faculty,
        'level': event.level,
        'field': event.field,
        'createdBy': event.createdBy,
        'createdAt': event.createdAt.toIso8601String(),
        'imageUrls': jsonEncode(event.imageUrls),
        'isGlobal': event.isGlobal ? 1 : 0,
        'reminder48hSent':
            (event.reminder48hSent || existingReminder48hSent) ? 1 : 0,
        'reminder12hSent':
            (event.reminder12hSent || existingReminder12hSent) ? 1 : 0,
        'reminder1hSent':
            (event.reminder1hSent || existingReminder1hSent) ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getUpcomingEvents() async {
    final db = await this.db;
    final cutoff =
        DateTime.now().subtract(_recentPastRetention).toIso8601String();
    return await db.query(
      'events',
      where: 'date > ?',
      whereArgs: [cutoff],
      orderBy: 'date DESC',
    );
  }

  /// Récupère tous les événements (pour l'initialisation des rappels)
  Future<List<Event>> getAllEvents() async {
    final db = await this.db;
    final results = await db.query('events');

    return results.map((map) {
      final imageUrlsStr = map['imageUrls'] as String?;
      final imageUrls = imageUrlsStr != null && imageUrlsStr.isNotEmpty
          ? List<String>.from(jsonDecode(imageUrlsStr) as List)
          : <String>[];

      return Event(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String,
        date: DateTime.parse(map['date'] as String),
        location: map['location'] as String,
        faculty: map['faculty'] as String,
        level: map['level'] as String,
        field: map['field'] as String,
        createdBy: map['createdBy'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        imageUrls: imageUrls,
        isGlobal: (map['isGlobal'] as int?) == 1,
        reminder48hSent: (map['reminder48hSent'] as int? ?? 0) == 1,
        reminder12hSent: (map['reminder12hSent'] as int? ?? 0) == 1,
        reminder1hSent: (map['reminder1hSent'] as int? ?? 0) == 1,
      );
    }).toList();
  }

  Future<void> deleteExpiredEvents() async {
    final db = await this.db;
    final cutoff =
        DateTime.now().subtract(_recentPastRetention).toIso8601String();
    await db.delete(
      'events',
      where: 'date < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> reconcileUpcomingEvents(List<Event> events) async {
    final db = await this.db;
    final cutoff =
        DateTime.now().subtract(_recentPastRetention).toIso8601String();
    final incomingIds = events.map((event) => event.id).toSet();

    if (incomingIds.isEmpty) {
      await db.delete(
        'events',
        where: 'date > ?',
        whereArgs: [cutoff],
      );
      return;
    }

    final placeholders = List.filled(incomingIds.length, '?').join(', ');
    await db.delete(
      'events',
      where: 'date > ? AND id NOT IN ($placeholders)',
      whereArgs: [cutoff, ...incomingIds],
    );
  }

  Future<void> deleteEvent(String eventId) async {
    final db = await this.db;
    await db.delete('events', where: 'id = ?', whereArgs: [eventId]);
  }

  Future<void> updateReminderSent(String eventId, String type) async {
    final db = await this.db;
    await db.update(
      'events',
      {type: 1},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }
}
