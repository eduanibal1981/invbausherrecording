import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Tracks a pending upload with its metadata
class PendingUpload {
  final String id;
  final Uint8List bytes;
  final String pcid;
  final String type; // 'ecg', 'vascular', 'vascular_video'
  final DateTime startedAt;
  UploadStatus status;
  String? error;
  int retryCount;

  PendingUpload({
    required this.id,
    required this.bytes,
    required this.pcid,
    required this.type,
    DateTime? startedAt,
    this.status = UploadStatus.pending,
    this.error,
    this.retryCount = 0,
  }) : startedAt = startedAt ?? DateTime.now();
}

enum UploadStatus { pending, uploading, success, failed }

/// Singleton service for managing background uploads
class BackgroundUploadService extends ChangeNotifier {
  static final BackgroundUploadService _instance =
      BackgroundUploadService._internal();
  factory BackgroundUploadService() => _instance;
  BackgroundUploadService._internal();

  final Map<String, PendingUpload> _pendingUploads = {};
  final List<String> _completedIds = [];
  final List<String> _failedIds = [];

  /// Get all pending uploads for a specific pcid and type
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

  /// Get count of pending uploads
  int get pendingCount => _pendingUploads.values
      .where(
        (u) =>
            u.status == UploadStatus.pending ||
            u.status == UploadStatus.uploading,
      )
      .length;

  /// Get count of failed uploads
  int get failedCount => _failedIds.length;

  /// Check if there are any active uploads
  bool get hasActiveUploads => _pendingUploads.values.any(
    (u) =>
        u.status == UploadStatus.pending || u.status == UploadStatus.uploading,
  );

  /// Add a new upload to the queue
  String addUpload({
    required Uint8List bytes,
    required String pcid,
    required String type,
  }) {
    final id = '${pcid}_${type}_${DateTime.now().millisecondsSinceEpoch}';
    _pendingUploads[id] = PendingUpload(
      id: id,
      bytes: bytes,
      pcid: pcid,
      type: type,
    );
    notifyListeners();
    return id;
  }

  /// Update upload status
  void updateStatus(String id, UploadStatus status, {String? error}) {
    if (_pendingUploads.containsKey(id)) {
      _pendingUploads[id]!.status = status;
      _pendingUploads[id]!.error = error;

      if (status == UploadStatus.success) {
        _completedIds.add(id);
        // Remove from pending after a short delay to allow UI to show success
        Future.delayed(const Duration(seconds: 2), () {
          _pendingUploads.remove(id);
          notifyListeners();
        });
      } else if (status == UploadStatus.failed) {
        _failedIds.add(id);
      }

      notifyListeners();
    }
  }

  /// Remove a pending upload
  void removeUpload(String id) {
    _pendingUploads.remove(id);
    _failedIds.remove(id);
    notifyListeners();
  }

  /// Retry a failed upload
  void retryUpload(String id) {
    if (_pendingUploads.containsKey(id)) {
      _pendingUploads[id]!.status = UploadStatus.pending;
      _pendingUploads[id]!.error = null;
      _pendingUploads[id]!.retryCount++;
      _failedIds.remove(id);
      notifyListeners();
    }
  }

  /// Clear all completed uploads
  void clearCompleted() {
    _completedIds.clear();
    notifyListeners();
  }

  /// Get upload by ID
  PendingUpload? getUpload(String id) => _pendingUploads[id];

  /// Clear all uploads for a specific pcid and type
  void clearUploadsFor(String pcid, String type) {
    _pendingUploads.removeWhere(
      (id, upload) => upload.pcid == pcid && upload.type == type,
    );
    notifyListeners();
  }
}
