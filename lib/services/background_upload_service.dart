import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudinary_service.dart';

/// Tracks a pending upload with its metadata
class PendingUpload {
  final String id;
  final String filePath; // Path to the local file
  final String pcid;
  final String type; // 'ecg', 'vascular', 'vascular_video'
  final DateTime startedAt;
  UploadStatus status;
  String? error;
  int retryCount;

  PendingUpload({
    required this.id,
    required this.filePath,
    required this.pcid,
    required this.type,
    DateTime? startedAt,
    this.status = UploadStatus.pending,
    this.error,
    this.retryCount = 0,
  }) : startedAt = startedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'pcid': pcid,
    'type': type,
    'startedAt': startedAt.toIso8601String(),
    'status': status.index,
    'error': error,
    'retryCount': retryCount,
  };

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
    id: json['id'],
    filePath: json['filePath'],
    pcid: json['pcid'],
    type: json['type'],
    startedAt: DateTime.parse(json['startedAt']),
    status: UploadStatus.values[json['status']],
    error: json['error'],
    retryCount: json['retryCount'] ?? 0,
  );
}

enum UploadStatus { pending, uploading, success, failed }

/// Singleton service for managing persistent upload queue
class BackgroundUploadService extends ChangeNotifier {
  static final BackgroundUploadService _instance =
      BackgroundUploadService._internal();
  factory BackgroundUploadService() => _instance;
  BackgroundUploadService._internal() {
    _init();
  }

  Map<String, PendingUpload> _pendingUploads = {};
  bool _isInitialized = false;
  static const String _prefsKey = 'pending_uploads_queue';

  Future<void> _init() async {
    await _loadFromPrefs();
    _isInitialized = true;
    notifyListeners();
  }

  /// Get pending uploads, ensuring service is initialized
  List<PendingUpload> getPendingUploads(String pcid, String type) {
    return _pendingUploads.values
        .where(
          (u) =>
              u.pcid == pcid &&
              u.type == type &&
              u.status != UploadStatus.success,
        )
        .toList();
  }

  /// Get all pending uploads grouped by patient
  Map<String, List<PendingUpload>> getAllPendingUploads() {
    final grouped = <String, List<PendingUpload>>{};
    for (var upload in _pendingUploads.values) {
      if (upload.status != UploadStatus.success) {
        if (!grouped.containsKey(upload.pcid)) {
          grouped[upload.pcid] = [];
        }
        grouped[upload.pcid]!.add(upload);
      }
    }
    return grouped;
  }

  int get pendingCount => _pendingUploads.values
      .where(
        (u) =>
            u.status == UploadStatus.pending ||
            u.status == UploadStatus.uploading,
      )
      .length;

  /// Add a file to the persistent queue
  Future<String> addToQueue({
    required String sourcePath, // Original path from picker
    required Uint8List? bytes, // Optional: for Web support if needed later
    required String pcid,
    required String type,
  }) async {
    // generating ID
    final id = '${pcid}_${type}_${DateTime.now().millisecondsSinceEpoch}';

    String savedPath = sourcePath;

    if (!kIsWeb) {
      // On mobile/desktop, copy file to app documents to ensure persistence
      final directory = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${directory.path}/pending_uploads');
      if (!await uploadsDir.exists()) {
        await uploadsDir.create(recursive: true);
      }

      final fileName = sourcePath.split(Platform.pathSeparator).last;
      // Ensure unique filename
      final newPath = '${uploadsDir.path}/${id}_$fileName';

      // Copy the file
      await File(sourcePath).copy(newPath);
      savedPath = newPath;
    }
    // For web, we might need a different strategy, but assuming this is Windows/Mobile per user context.
    // If only bytes were provided (unlikely with this refactor), we'd need to handle that.

    final upload = PendingUpload(
      id: id,
      filePath: savedPath,
      pcid: pcid,
      type: type,
    );

    _pendingUploads[id] = upload;
    await _saveToPrefs();
    notifyListeners();
    return id;
  }

  /// Update upload status and save
  Future<void> updateStatus(
    String id,
    UploadStatus status, {
    String? error,
  }) async {
    if (_pendingUploads.containsKey(id)) {
      _pendingUploads[id]!.status = status;
      _pendingUploads[id]!.error = error;

      if (status == UploadStatus.success) {
        // Optionally delete local file on success to save space
        // File(_pendingUploads[id]!.filePath).delete().ignore();
      }

      await _saveToPrefs();
      notifyListeners();

      // If success, remove from map after a short delay (or keep for history until cleared manually)
      if (status == UploadStatus.success) {
        Future.delayed(const Duration(seconds: 2), () async {
          _pendingUploads.remove(id);
          await _saveToPrefs();
          notifyListeners();
        });
      }
    }
  }

  /// Remove an upload (e.g. user cancelled)
  Future<void> removeUpload(String id) async {
    final upload = _pendingUploads[id];
    if (upload != null) {
      if (!kIsWeb) {
        try {
          final file = File(upload.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting local file: $e');
        }
      }
      _pendingUploads.remove(id);
      await _saveToPrefs();
      notifyListeners();
    }
  }

  /// Retry a failed upload
  Future<void> retryUpload(String id) async {
    if (_pendingUploads.containsKey(id)) {
      _pendingUploads[id]!.status = UploadStatus.pending;
      _pendingUploads[id]!.error = null;
      _pendingUploads[id]!.retryCount++;
      await _saveToPrefs();
      notifyListeners();
    }
  }

  // --- Persistence ---

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(
      _pendingUploads.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_prefsKey, jsonString);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonString);
        _pendingUploads = decoded.map(
          (key, value) => MapEntry(key, PendingUpload.fromJson(value)),
        );
      } catch (e) {
        debugPrint('Error loading pending uploads: $e');
      }
    }
  }

  /// Get upload by ID
  PendingUpload? getUpload(String id) => _pendingUploads[id];

  /// Clear all uploads for a specific pcid and type
  Future<void> clearUploadsFor(String pcid, String type) async {
    final toRemove = _pendingUploads.entries
        .where((e) => e.value.pcid == pcid && e.value.type == type)
        .map((e) => e.key)
        .toList();
    for (var id in toRemove) {
      // Cleanup file
      final upload = _pendingUploads[id];
      if (upload != null && !kIsWeb) {
        try {
          File(upload.filePath).deleteSync();
        } catch (_) {}
      }
      _pendingUploads.remove(id);
    }
    await _saveToPrefs();
    notifyListeners();
  }

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  /// Process the queue sequentially
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    notifyListeners();

    try {
      final allPending = getAllPendingUploads();

      // Flatten logic: Iterate through all pending items
      List<PendingUpload> uploadsToProcess = [];
      allPending.forEach((key, list) {
        uploadsToProcess.addAll(list);
      });

      for (final upload in uploadsToProcess) {
        // Skip if already success (shouldn't happen with getPending but safe check)
        if (upload.status == UploadStatus.success) continue;

        // Determine if we should stop (could add a cancel flag later)

        await updateStatus(upload.id, UploadStatus.uploading);

        try {
          final file = File(upload.filePath);
          if (!await file.exists()) {
            await updateStatus(
              upload.id,
              UploadStatus.failed,
              error: 'File not found',
            );
            continue;
          }

          final bytes = await file.readAsBytes();

          dynamic result;
          if (upload.type == 'ecg') {
            result = await CloudinaryService.uploadEcgImage(
              imageBytes: bytes,
              pcid: upload.pcid,
            );
          } else if (upload.type == 'vascular') {
            result = await CloudinaryService.uploadDopplerImage(
              imageBytes: bytes,
              pcid: upload.pcid,
            );
          } else if (upload.type == 'vascular_video') {
            result = await CloudinaryService.uploadDopplerVideo(
              videoBytes: bytes,
              pcid: upload.pcid,
            );
          }

          if (result != null && result.success) {
            await updateStatus(upload.id, UploadStatus.success);
          } else {
            await updateStatus(
              upload.id,
              UploadStatus.failed,
              error: result?.message ?? 'Upload failed',
            );
          }
        } catch (e) {
          await updateStatus(
            upload.id,
            UploadStatus.failed,
            error: e.toString(),
          );
        }

        // Artificial delay to prevent flooding
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
