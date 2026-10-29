import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/screening_result.dart';
import 'auth_store.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // NOTE: Change this to your local IP (http://10.0.2.2:5000) if testing locally
  static const String baseUrl = 'https://ferry-undoing-sphinx.ngrok-free.dev';

  Map<String, String> _jsonHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
    final token = AuthStore.instance.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, String> _authHeaders() {
    final headers = <String, String>{'ngrok-skip-browser-warning': 'true'};
    final token = AuthStore.instance.token;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<AuthResult> signUp({required String name, required String email, required String password}) async {
    final res = await http.post(Uri.parse('$baseUrl/auth/signup'), headers: _jsonHeaders(), body: jsonEncode({'name': name, 'email': email, 'password': password}));
    return _parseAuth(res);
  }

  Future<AuthResult> signIn({required String email, required String password}) async {
    final res = await http.post(Uri.parse('$baseUrl/auth/signin'), headers: _jsonHeaders(), body: jsonEncode({'email': email, 'password': password}));
    return _parseAuth(res);
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final res = await http.post(Uri.parse('$baseUrl/auth/forgot'), headers: _jsonHeaders(), body: jsonEncode({'email': email}));
    return _decode(res);
  }

  Future<ChatReply> chat({required String message, List<Map<String, String>> history = const []}) async {
    final res = await http.post(Uri.parse('$baseUrl/chat/'), headers: _jsonHeaders(), body: jsonEncode({'message': message, 'history': history}));
    final data = _decode(res);
    return ChatReply(text: data['reply'] as String? ?? '(no reply)', suggestions: (data['suggestions'] as List?)?.cast<String>() ?? const []);
  }

  Future<ScreeningResult> assessScreen(Map<String, dynamic> payload) async {
    final res = await http.post(Uri.parse('$baseUrl/screen/assess'), headers: _jsonHeaders(), body: jsonEncode(payload));
    return ScreeningResult.fromJson(_decode(res));
  }

  Future<Map<String, dynamic>> predictFromBytes({required Map<String, List<int>> images}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict/'));
    request.headers.addAll(_authHeaders());
    images.forEach((key, bytes) { request.files.add(http.MultipartFile.fromBytes(key, bytes, filename: '$key.jpg')); });
    final streamed = await request.send();
    return _decode(await http.Response.fromStream(streamed));
  }

  Future<List<Map<String, dynamic>>> listScans({int limit = 50}) async {
    final res = await http.get(Uri.parse('$baseUrl/scans?limit=$limit'), headers: _authHeaders());
    final list = (_decode(res)['scans'] as List?) ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> createScan({
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> predictions,
    Map<String, dynamic>? screening,
    Map<String, List<int>>? images,
    Map<String, dynamic>? rawProbs,     // <-- NEW: Accepts raw probabilities
    String? modelVersion,              // <-- NEW: Accepts model version
    String note = '',
    String? timestamp,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scans'));
    request.headers.addAll(_authHeaders());
    
    request.fields['summary'] = jsonEncode(summary);
    request.fields['predictions'] = jsonEncode(predictions);
    if (screening != null) request.fields['screening'] = jsonEncode(screening);
    if (note.isNotEmpty) request.fields['note'] = note;
    if (timestamp != null) request.fields['timestamp'] = timestamp;

    // <-- NEW: Send the raw probs and version to the backend
    if (rawProbs != null) request.fields['raw_probs'] = jsonEncode(rawProbs);
    if (modelVersion != null) request.fields['model_version'] = modelVersion;

    if (images != null) {
      images.forEach((key, bytes) {
        request.files.add(http.MultipartFile.fromBytes(key, bytes, filename: '$key.jpg'));
      });
    }

    final streamed = await request.send();
    return _decode(await http.Response.fromStream(streamed));
  }

  Future<void> deleteScan(String id) async {
    await http.delete(Uri.parse('$baseUrl/scans/$id'), headers: _authHeaders());
  }

  Future<void> clearScans() async {
    await http.delete(Uri.parse('$baseUrl/scans'), headers: _authHeaders());
  }

  AuthResult _parseAuth(http.Response res) {
    final data = _decode(res);
    if (res.statusCode >= 400) throw ApiException(data['error'] as String? ?? 'Request failed');
    return AuthResult(token: data['token'] as String? ?? '', userId: (data['user']?['id'] as String?) ?? '', name: (data['user']?['name'] as String?) ?? '', email: (data['user']?['email'] as String?) ?? '');
  }

  Map<String, dynamic> _decode(http.Response res) {
    try { return jsonDecode(res.body.isEmpty ? '{}' : res.body) as Map<String, dynamic>; } catch (_) { throw ApiException('Invalid response (${res.statusCode})'); }
  }
}

class AuthResult {
  final String token, userId, name, email;
  const AuthResult({required this.token, required this.userId, required this.name, required this.email});
}

class ChatReply {
  final String text;
  final List<String> suggestions;
  const ChatReply({required this.text, this.suggestions = const []});
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}