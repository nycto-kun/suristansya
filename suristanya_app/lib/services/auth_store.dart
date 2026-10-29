import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  AuthStore._();
  static final AuthStore instance = AuthStore._();

  static const _kToken = 'auth_token';
  static const _kUserId = 'auth_user_id';
  static const _kName = 'auth_name';
  static const _kEmail = 'auth_email';
  static const _kAge = 'auth_age';

  String? _token;
  String? _userId;
  String? _name;
  String? _email;
  String? _age;

  String? get token => _token;
  String? get userId => _userId;
  String? get name => _name;
  String? get email => _email;
  String? get age => _age;
  bool get isSignedIn => _token != null && _token!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    _userId = prefs.getString(_kUserId);
    _name = prefs.getString(_kName);
    _email = prefs.getString(_kEmail);
    _age = prefs.getString(_kAge);
  }

  Future<void> save({
    required String token,
    required String userId,
    required String name,
    required String email,
    required String age,
  }) async {
    _token = token;
    _userId = userId;
    _name = name;
    _email = email;
    _age = age;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUserId, userId);
    await prefs.setString(_kName, name);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kAge, age);
  }

  // UPDATE METHOD NOW INCLUDES EMAIL
  Future<void> updateProfile({
    required String name,
    required String email,
    required String age,
  }) async {
    _name = name;
    _email = email;
    _age = age;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kAge, age);
  }

  Future<void> clear() async {
    _token = null;
    _userId = null;
    _name = null;
    _email = null;
    _age = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kName);
    await prefs.remove(_kEmail);
    await prefs.remove(_kAge);
  }
}
