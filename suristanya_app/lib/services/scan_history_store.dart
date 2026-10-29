import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prediction.dart';
import '../models/scan_record.dart';
import '../models/screening_result.dart';
import 'api_service.dart';
import 'auth_store.dart';

class ScanHistoryStore {
  ScanHistoryStore._();
  static final ScanHistoryStore instance = ScanHistoryStore._();

  static const _kKey = 'scan_history';
  static const _maxRecords = 50;

  final List<ScanRecord> _records = [];
  bool _loaded = false;

  List<ScanRecord> get records => List.unmodifiable(_records);
  bool get isEmpty => _records.isEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _records..clear()..addAll(list.map((e) => ScanRecord.fromJson((e as Map).cast<String, dynamic>())));
      } catch (_) {
        _records.clear();
      }
    }
    _loaded = true;
  }

  Future<void> refreshFromServer() async {
    if (!AuthStore.instance.isSignedIn) return;
    try {
      final scans = await ApiService.instance.listScans(limit: _maxRecords);
      _records..clear()..addAll(scans.map(ScanRecord.fromJson));
      await _persist();
    } catch (_) {}
  }

  Future<ScanRecord> add({
    required Map<String, dynamic> apiResponse,
    ScreeningResult? screening,
    Map<String, List<int>>? images,
    Map<String, dynamic>? rawProbs,    // <-- NEW
    String? modelVersion,             // <-- NEW
  }) async {
    final summaryJson = (apiResponse['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final predictionsJson = (apiResponse['predictions'] as List?) ?? [];
    final timestamp = DateTime.now();

    if (AuthStore.instance.isSignedIn) {
      try {
        final saved = await ApiService.instance.createScan(
          summary: summaryJson,
          predictions: predictionsJson.map((p) => (p as Map).cast<String, dynamic>()).toList(),
          screening: screening?.toJson(),
          timestamp: timestamp.toIso8601String(),
          images: images,
          rawProbs: rawProbs,          // <-- NEW: Pass to API
          modelVersion: modelVersion,  // <-- NEW: Pass to API
        );
        final record = ScanRecord.fromJson(saved);
        _records.insert(0, record);
        if (_records.length > _maxRecords) _records.removeRange(_maxRecords, _records.length);
        await _persist();
        return record;
      } catch (_) {}
    }

    final record = ScanRecord(
      id: timestamp.microsecondsSinceEpoch.toString(),
      timestamp: timestamp,
      summary: HealthSummary.fromJson(summaryJson),
      predictions: predictionsJson.map((p) => Prediction.fromJson((p as Map).cast<String, dynamic>())).toList(),
      screening: screening,
    );

    _records.insert(0, record);
    if (_records.length > _maxRecords) _records.removeRange(_maxRecords, _records.length);
    await _persist();
    return record;
  }

  Future<void> updateNote(String id, String note) async {
    final idx = _records.indexWhere((r) => r.id == id);
    if (idx == -1) return;
    _records[idx] = _records[idx].copyWith(note: note.trim());
    await _persist();
  }

  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _persist();
    if (AuthStore.instance.isSignedIn) {
      try { await ApiService.instance.deleteScan(id); } catch (_) {}
    }
  }

  Future<void> clear() async {
    _records.clear();
    await _persist();
    if (AuthStore.instance.isSignedIn) {
      try { await ApiService.instance.clearScans(); } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_records.map((r) => r.toJson()).toList());
    await prefs.setString(_kKey, raw);
  }
}