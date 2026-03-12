import 'package:shared_preferences/shared_preferences.dart';
import 'package:injectable/injectable.dart';
import '../constants/app_constants.dart';

/// Service for managing local storage operations
@lazySingleton
class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // Theme
  Future<void> saveThemeMode(String themeMode) async {
    await _prefs.setString(AppConstants.themeKey, themeMode);
  }

  String? getThemeMode() {
    return _prefs.getString(AppConstants.themeKey);
  }

  // Language
  Future<void> saveLanguage(String languageCode) async {
    await _prefs.setString(AppConstants.languageKey, languageCode);
  }

  String? getLanguage() {
    return _prefs.getString(AppConstants.languageKey);
  }

  // Auth Token
  Future<void> saveAuthToken(String token) async {
    await _prefs.setString(AppConstants.authTokenKey, token);
  }

  String? getAuthToken() {
    return _prefs.getString(AppConstants.authTokenKey);
  }

  Future<void> clearAuthToken() async {
    await _prefs.remove(AppConstants.authTokenKey);
  }

  Future<void> removeAuthToken() async {
    await _prefs.remove(AppConstants.authTokenKey);
  }

  // Refresh Token
  Future<void> saveRefreshToken(String token) async {
    await _prefs.setString(AppConstants.refreshTokenKey, token);
  }

  String? getRefreshToken() {
    return _prefs.getString(AppConstants.refreshTokenKey);
  }

  Future<void> clearRefreshToken() async {
    await _prefs.remove(AppConstants.refreshTokenKey);
  }

  // User Data
  Future<void> saveUserData(String userData) async {
    await _prefs.setString(AppConstants.userKey, userData);
  }

  String? getUserData() {
    return _prefs.getString(AppConstants.userKey);
  }

  Future<void> clearUserData() async {
    await _prefs.remove(AppConstants.userKey);
  }

  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
