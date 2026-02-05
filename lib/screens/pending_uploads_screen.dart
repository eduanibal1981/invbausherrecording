import 'package:flutter/material.dart';
import '../services/background_upload_service.dart';

class PendingUploadsScreen extends StatefulWidget {
  const PendingUploadsScreen({super.key});

  @override
  State<PendingUploadsScreen> createState() => _PendingUploadsScreenState();
}

class _PendingUploadsScreenState extends State<PendingUploadsScreen> {
  final BackgroundUploadService _uploadService = BackgroundUploadService();

  @override
  void initState() {
    super.initState();
    _uploadService.addListener(_refresh);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _uploadAll() async {
    if (_uploadService.isProcessing) return;

    // Trigger processing in background service
    await _uploadService.processQueue();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload processing finished.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedUploads = _uploadService.getAllPendingUploads();
    final totalCount = groupedUploads.values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    final activeUpload = _findActiveUpload(groupedUploads);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Uploads'),
        actions: [
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: _uploadService.isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _uploadAll,
                      icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                      label: const Text(
                        'Upload All',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),
                    ),
            ),
        ],
      ),
      body: Stack(
        children: [
          groupedUploads.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No pending uploads',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: groupedUploads.length,
                  itemBuilder: (context, index) {
                    final pcid = groupedUploads.keys.elementAt(index);
                    final uploads = groupedUploads[pcid]!;

                    // Group stats
                    final ecgCount =
                        uploads.where((u) => u.type == 'ecg').length;
                    final vascularCount = uploads
                        .where((u) => u.type == 'vascular')
                        .length;
                    final videoCount = uploads
                        .where((u) => u.type == 'vascular_video')
                        .length;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ExpansionTile(
                        title: Text('Patient ID: $pcid'),
                        subtitle: Text(
                          '$ecgCount ECG • $vascularCount Vascular • $videoCount Videos',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        children: uploads.map((upload) {
                          return ListTile(
                            leading: _buildLeadingIcon(upload),
                            title: Text(
                              _safeFileName(upload.filePath),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: upload.status == UploadStatus.failed
                                ? Text(
                                    upload.error ?? 'Failed',
                                    style: const TextStyle(color: Colors.red),
                                  )
                                : Text(
                                    upload.status.toString().split('.').last,
                                  ),
                            trailing: upload.status == UploadStatus.uploading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () =>
                                        _uploadService.removeUpload(upload.id),
                                  ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
          if (_uploadService.isProcessing)
            Center(child: _buildUploadingBanner(activeUpload, totalCount)),
        ],
      ),
    );
  }

  PendingUpload? _findActiveUpload(
    Map<String, List<PendingUpload>> groupedUploads,
  ) {
    for (final uploads in groupedUploads.values) {
      for (final upload in uploads) {
        if (upload.status == UploadStatus.uploading) return upload;
      }
    }
    return null;
  }

  Widget _buildUploadingBanner(PendingUpload? upload, int totalCount) {
    final title = upload != null
        ? 'Uploading ${_typeLabel(upload.type)}'
        : 'Uploading images';
    final subtitle = upload != null
        ? 'Patient ID: ${upload.pcid} • ${_safeFileName(upload.filePath)}'
        : 'Items remaining: $totalCount';

    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade100),
            boxShadow: const [
              BoxShadow(
                color: Color.fromARGB(40, 0, 0, 0),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    if (type == 'ecg') return 'ECG image';
    if (type == 'vascular') return 'Doppler image';
    if (type == 'vascular_video') return 'Doppler video';
    return 'image';
  }

  String _safeFileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash == -1) return path;
    final name = normalized.substring(lastSlash + 1);
    return name.isEmpty ? path : name;
  }

  Widget _buildLeadingIcon(PendingUpload upload) {
    if (upload.type == 'ecg')
      return const Icon(Icons.monitor_heart, color: Colors.red);
    if (upload.type == 'vascular')
      return const Icon(Icons.water_drop, color: Colors.blue);
    if (upload.type == 'vascular_video')
      return const Icon(Icons.videocam, color: Colors.purple);
    return const Icon(Icons.file_present);
  }
}
