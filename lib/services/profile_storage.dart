import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class ProfileStorage {
  static const String _key = 'user_profile';

  static Future<void> saveProfile(Profile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  static Future<Profile?> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data != null) {
      return Profile.fromJson(jsonDecode(data));
    }
    return null;
  }

  static Future<void> clearProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
