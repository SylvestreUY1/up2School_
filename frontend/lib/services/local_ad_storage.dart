import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/ad_model.dart';
import '../models/user.dart';
import '../utils/academic_targeting.dart';

class LocalAdStorage {
  static final LocalAdStorage _instance = LocalAdStorage._internal();
  factory LocalAdStorage() => _instance;
  LocalAdStorage._internal();

  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ads.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ads (
            id TEXT PRIMARY KEY,
            title TEXT,
            description TEXT,
            imageUrl TEXT,
            targetUrl TEXT,
            faculty TEXT,
            level TEXT,
            field TEXT,
            isGlobal INTEGER,
            isActive INTEGER,
            clicks INTEGER,
            startDate TEXT,
            endDate TEXT,
            audienceKey TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE ads ADD COLUMN faculty TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE ads ADD COLUMN level TEXT DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE ads ADD COLUMN field TEXT DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE ads ADD COLUMN isGlobal INTEGER DEFAULT 1',
          );
          await db.execute(
            "ALTER TABLE ads ADD COLUMN audienceKey TEXT DEFAULT 'guest'",
          );
          await db.delete('ads');
        }
      },
    );
  }

  Future<void> insertAd(AdModel ad, {UserModel? user}) async {
    final db = await this.db;
    await db.insert(
        'ads',
        {
          'id': ad.id,
          'title': ad.title,
          'description': ad.description,
          'imageUrl': ad.imageUrl,
          'targetUrl': ad.targetUrl,
          'faculty': ad.faculty,
          'level': ad.level,
          'field': ad.field,
          'isGlobal': ad.isGlobal ? 1 : 0,
          'isActive': ad.isActive ? 1 : 0,
          'clicks': ad.clicks,
          'startDate': ad.startDate?.toIso8601String(),
          'endDate': ad.endDate?.toIso8601String(),
          'audienceKey': AcademicTargeting.audienceKey(user),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AdModel>> getActiveAds({UserModel? user}) async {
    final db = await this.db;
    final audienceKey = AcademicTargeting.audienceKey(user);
    await deleteExpiredAds(audienceKey: audienceKey);
    final List<Map<String, dynamic>> maps = await db.query(
      'ads',
      where: 'isActive = 1 AND audienceKey = ?',
      whereArgs: [audienceKey],
      orderBy: 'startDate DESC',
    );
    final now = DateTime.now();

    return maps
        .map((map) => AdModel.fromMap(map['id']?.toString() ?? '', map))
        .where((ad) {
      final startsBeforeNow =
          ad.startDate == null || !ad.startDate!.isAfter(now);
      final endsAfterNow = ad.endDate == null || !ad.endDate!.isBefore(now);
      return ad.isActive && startsBeforeNow && endsAfterNow;
    }).toList();
  }

  Future<void> deleteExpiredAds({String? audienceKey}) async {
    final db = await this.db;
    final now = DateTime.now().toIso8601String();
    if (audienceKey == null || audienceKey.isEmpty) {
      await db.delete('ads', where: 'endDate < ?', whereArgs: [now]);
      return;
    }

    await db.delete(
      'ads',
      where: 'endDate < ? OR audienceKey != ?',
      whereArgs: [now, audienceKey],
    );
  }

  Future<void> deleteAd(String adId) async {
    final db = await this.db;
    await db.delete('ads', where: 'id = ?', whereArgs: [adId]);
  }
}
