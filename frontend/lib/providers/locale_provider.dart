import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider() {
    _load();
  }

  static const String preferenceKey = 'app_locale_code';

  Locale? _locale;
  bool _loaded = false;

  Locale? get locale => _locale;
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    _locale = await LocalePreferences.readSavedLocale();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLocaleCode(String? languageCode) async {
    final nextLocale = languageCode == null || languageCode.isEmpty
        ? null
        : Locale(languageCode);

    if (_locale?.languageCode == nextLocale?.languageCode &&
        (_locale == null) == (nextLocale == null)) {
      return;
    }

    _locale = nextLocale;
    notifyListeners();
    await LocalePreferences.saveLocale(nextLocale);
  }
}

class LocalePreferences {
  static Future<Locale?> readSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(LocaleProvider.preferenceKey);
    if (code == null || code.isEmpty) {
      return null;
    }

    return Locale(code);
  }

  static Future<void> saveLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(LocaleProvider.preferenceKey);
      return;
    }

    await prefs.setString(LocaleProvider.preferenceKey, locale.languageCode);
  }

  static Future<Locale> effectiveLocale() async {
    final savedLocale = await readSavedLocale();
    return savedLocale ??
        AppLocalizations.resolvePreferredLocale(
            PlatformDispatcher.instance.locales);
  }
}
