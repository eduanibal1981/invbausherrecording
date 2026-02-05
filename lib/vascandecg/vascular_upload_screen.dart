import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cloudinary_service.dart';
import '../services/background_upload_service.dart';

class VascularUploadScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const VascularUploadScreen({
    super.key,
    required this.patient,
    this.staffRole,
  });

  @override
  State<VascularUploadScreen> createState() => _VascularUploadScreenState();
}

class _VascularUploadScreenState extends State<VascularUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final BackgroundUploadService _uploadService = BackgroundUploadService();

  // Local preview (not yet uploaded)
  List<XFile> _selectedFiles = [];

  bool _isLoading = false;
  List<Map<String, dynamic>> _uploadedImages = [];

  // Vascular Access Type
  String? _currentVaccess;
  String? _selectedVaccess;
  bool _isSavingVaccess = false;

  final List<String> _vaccessOptions = ['AVF', 'AVG', 'Perm. Cath'];

  String get _pcid => widget.patient['pcid'].toString();

  @override
  void initState() {
    super.initState();
    _loadCurrentVaccess();
    _fetchUploadedImages();
    _uploadService.addListener(_onUploadServiceChanged);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_onUploadServiceChanged);
    super.dispose();
  }

  void _onUploadServiceChanged() {
    if (mounted) {
      setState(() {});
      // Refresh images if any upload completed
      final pending = _uploadService.getPendingUploads(_pcid, 'vascular');
      final pendingVideo = _uploadService.getPendingUploads(
        _pcid,
        'vascular_video',
      );
      if (pending.any((p) => p.status == UploadStatus.success) ||
          pendingVideo.any((p) => p.status == UploadStatus.success)) {
        _fetchUploadedImages();
      }
    }
  }

  void _loadCurrentVaccess() {
    final vaccess = widget.patient['vaccess']?.toString();
    setState(() {
      _currentVaccess = vaccess;
      _selectedVaccess = vaccess;
    });
  }

  Future<void> _saveVaccess() async {
    if (_selectedVaccess == null || _selectedVaccess == _currentVaccess) return;

    setState(() => _isSavingVaccess = true);
    try {
      await Supabase.instance.client
          .from('patients')
          .update({'vaccess': _selectedVaccess})
          .eq('pcid', widget.patient['pcid']);

      setState(() {
        _currentVaccess = _selectedVaccess;
        widget.patient['vaccess'] = _selectedVaccess;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vascular access updated to $_selectedVaccess'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving vascular access: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingVaccess = false);
    }
  }

  Future<void> _fetchUploadedImages() async {
    setState(() => _isLoading = true);
    try {
      final images = await CloudinaryService.fetchDopplerImages(_pcid);
      setState(() => _uploadedImages = images);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading images: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFiles(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        // Camera capture
        final XFile? image = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 90,
        );
        if (image != null) {
          setState(() {
            _selectedFiles.add(image);
          });
        }
      } else {
        // Multi-select from gallery
        final List<XFile> files = await _picker.pickMultipleMedia();
        if (files.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(files);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking files: $e')));
      }
    }
  }

  bool _isVideo(String path) {
    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.avi') ||
        lowerPath.endsWith('.mkv');
  }

  /// Save selected files to queue
  Future<void> _saveToQueue() async {
    if (_selectedFiles.isEmpty) return;

    int count = 0;
    for (final file in _selectedFiles) {
      final isVideo = _isVideo(file.path);
      final type = isVideo ? 'vascular_video' : 'vascular';

      await _uploadService.addToQueue(
        sourcePath: file.path,
        bytes: null,
        pcid: _pcid,
        type: type,
      );
      count++;
    }

    setState(() {
      _selectedFiles.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count files saved to pending queue.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteImage(Map<String, dynamic> image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image'),
        content: const Text('Are you sure you want to delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final result = await CloudinaryService.deleteDopplerImage(image);
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Image deleted'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUploadedImages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Failed to delete image'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFullImage(String imageUrl) {
    final lowerUrl = imageUrl.toLowerCase();
    final isVideo =
        lowerUrl.endsWith('.mp4') ||
        lowerUrl.endsWith('.mov') ||
        lowerUrl.endsWith('.avi') ||
        lowerUrl.endsWith('.mkv');

    if (isVideo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video playback not supported in this version.'),
          ),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePendingVascular = _uploadService.getPendingUploads(
      _pcid,
      'vascular',
    );
    final activePendingVideo = _uploadService.getPendingUploads(
      _pcid,
      'vascular_video',
    );
    final allActivePending = [...activePendingVascular, ...activePendingVideo];
    final uploadingCount = allActivePending
        .where(
          (p) =>
              p.status == UploadStatus.pending ||
              p.status == UploadStatus.uploading,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patient['name'] ?? 'Unknown'),
            Text(
              'ID: ${widget.patient['pcid']}',
              style: const TextStyle(fontSize: 12),
            ),
            const Text(
              '         == Vascular ==',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          // Background upload indicator
          if (uploadingCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$uploadingCount',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Vascular Access Type Section
          Card(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.purple.shade100),
            ),
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bloodtype, color: Colors.purple.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Current Vascular Access',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedVaccess,
                          decoration: InputDecoration(
                            labelText: 'Access Type',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          items: _vaccessOptions
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedVaccess = val),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            (_isSavingVaccess ||
                                _selectedVaccess == null ||
                                _selectedVaccess == _currentVaccess)
                            ? null
                            : _saveVaccess,
                        icon: _isSavingVaccess
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSavingVaccess ? 'Saving...' : 'Save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.purple,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_currentVaccess != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Current: $_currentVaccess',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Upload Section
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Upload New Images/Videos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Image Source Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFiles(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Capture'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFiles(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Selected Files Preview (local, not yet uploaded)
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Selected: ${_selectedFiles.length} files',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final file = _selectedFiles[index];
                          final isVideo = _isVideo(file.path);
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isVideo
                                    ? Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.black,
                                        child: const Center(
                                          child: Icon(
                                            Icons.videocam,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                      )
                                    : Image.file(
                                        File(file.path),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              if (isVideo)
                                const Positioned.fill(
                                  child: Center(
                                    child: Icon(
                                      Icons.play_circle,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedFiles.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    color: Colors.black54,
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _selectedFiles.clear();
                            }),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveToQueue,
                            icon: const Icon(Icons.save_as),
                            label: Text('Save ${_selectedFiles.length} Items'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Pending uploads (optimistic UI)
                  if (allActivePending.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.pending_actions,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Pending Uploads: ${allActivePending.length} files',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: allActivePending.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final pending = allActivePending[index];
                          final isVideo = pending.type == 'vascular_video';
                          final file = File(pending.filePath);

                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isVideo
                                    ? Container(
                                        width: 80,
                                        height: 80,
                                        color: Colors.black87,
                                        child: const Icon(
                                          Icons.videocam,
                                          color: Colors.white54,
                                        ),
                                      )
                                    : ColorFiltered(
                                        colorFilter: ColorFilter.mode(
                                          Colors.black.withOpacity(0.1),
                                          BlendMode.darken,
                                        ),
                                        child: file.existsSync()
                                            ? Image.file(
                                                file,
                                                height: 80,
                                                width: 80,
                                                fit: BoxFit.cover,
                                              )
                                            : const SizedBox(
                                                width: 80,
                                                height: 80,
                                                child: Icon(Icons.broken_image),
                                              ),
                                      ),
                              ),
                              if (isVideo)
                                const Positioned.fill(
                                  child: Center(
                                    child: Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _uploadService.removeUpload(pending.id),
                                  color: Colors.white,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Divider
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Uploaded Images'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),

          // Images Grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _uploadedImages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No images uploaded yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchUploadedImages,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _uploadedImages.length,
                      itemBuilder: (context, index) {
                        final image = _uploadedImages[index];
                        final thumbnailUrl =
                            image['thumbnail_url'] ?? image['piclink'];
                        final fullUrl = image['large_url'] ?? image['piclink'];
                        final isVideo =
                            fullUrl.toLowerCase().endsWith('.mp4') ||
                            fullUrl.toLowerCase().endsWith('.mov') ||
                            fullUrl.toLowerCase().endsWith('.avi');

                        return GestureDetector(
                          onTap: () => _showFullImage(fullUrl),
                          onLongPress: () => _deleteImage(image),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  thumbnailUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stack) {
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.broken_image,
                                        color: Colors.grey,
                                      ),
                                    );
                                  },
                                ),
                                if (isVideo)
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                Positioned(
                                  right: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.zoom_in,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Helper class to hold selected file data
