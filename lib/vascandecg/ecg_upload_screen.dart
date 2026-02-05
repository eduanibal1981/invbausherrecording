import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/cloudinary_service.dart';
import '../services/background_upload_service.dart';

class EcgUploadScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const EcgUploadScreen({super.key, required this.patient, this.staffRole});

  @override
  State<EcgUploadScreen> createState() => _EcgUploadScreenState();
}

class _EcgUploadScreenState extends State<EcgUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final BackgroundUploadService _uploadService = BackgroundUploadService();

  // Selected images ready to queue (local preview)
  List<XFile> _selectedFiles = [];

  bool _isLoading = false;
  List<Map<String, dynamic>> _uploadedImages = [];

  // Note editing
  final TextEditingController _noteController = TextEditingController();

  String get _pcid => widget.patient['pcid'].toString();

  @override
  void initState() {
    super.initState();
    _fetchUploadedImages();
    _uploadService.addListener(_onUploadServiceChanged);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _uploadService.removeListener(_onUploadServiceChanged);
    super.dispose();
  }

  void _onUploadServiceChanged() {
    if (mounted) {
      setState(() {});
      // Refresh images if any upload completed (handled by separate process now, but good to keep sync)
      final pending = _uploadService.getPendingUploads(_pcid, 'ecg');
      if (pending.any((p) => p.status == UploadStatus.success)) {
        _fetchUploadedImages();
      }
    }
  }

  Future<void> _fetchUploadedImages() async {
    setState(() => _isLoading = true);
    try {
      final images = await CloudinaryService.fetchEcgImages(_pcid);
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

  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        // Single camera capture
        final XFile? image = await _picker.pickImage(
          source: ImageSource.camera,
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
        final List<XFile> images = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 90,
        );
        if (images.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(images);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking images: $e')));
      }
    }
  }

  /// Save selected files to the upload queue and clear selection
  Future<void> _saveToQueue() async {
    if (_selectedFiles.isEmpty) return;

    int addedCount = 0;
    for (final file in _selectedFiles) {
      Uint8List? fileBytes;
      try {
        // On web we need to preload bytes if they aren't available immediately
        // But _selectedFiles is List<XFile>, so we can read bytes
        fileBytes = await file.readAsBytes();
      } catch (e) {
        debugPrint('Error reading file bytes: $e');
      }

      await _uploadService.addToQueue(
        sourcePath: file.path,
        bytes: fileBytes, // Pass bytes for Web
        pcid: _pcid,
        type: 'ecg',
      );
      addedCount++;
    }

    setState(() {
      _selectedFiles.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$addedCount images saved to pending queue.'),
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
        content: const Text('Are you sure you want to delete this ECG?'),
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
      final result = await CloudinaryService.deleteEcgImage(image);
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
    final activePending = _uploadService.getPendingUploads(_pcid, 'ecg');

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
            const Text('         == ECG ==', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Review Note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ensure grid lines are clearly visible in the photo.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
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
                    'Add New ECG',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Image Source Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImages(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImages(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery (Multi)'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Image Preview (selected, not yet queued)
                  if (_selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Selected: ${_selectedFiles.length} images',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedFiles.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_selectedFiles[index].path),
                                  height: 100,
                                  width: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
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
                            child: const Text('Clear All'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveToQueue,
                            icon: const Icon(Icons.save_as),
                            label: const Text('Save to Queue'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Pending uploads (local queue)
                  if (activePending.isNotEmpty) ...[
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
                          'Pending Uploads: ${activePending.length} images',
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
                        itemCount: activePending.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final pending = activePending[index];
                          final file = File(pending.filePath);

                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                  child: kIsWeb
                                      ? Image.network(
                                          pending.filePath,
                                          height: 80,
                                          width: 80,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.broken_image),
                                        )
                                      : (file.existsSync()
                                          ? Image.file(
                                              file,
                                              height: 80,
                                              width: 80,
                                              fit: BoxFit.cover,
                                            )
                                          : const SizedBox(
                                              height: 80,
                                              width: 80,
                                              child: Icon(Icons.broken_image),
                                            )),
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
                  child: Text('Uploaded ECGs'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          const SizedBox(height: 8),

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
                          Icons.monitor_heart_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No ECGs uploaded yet',
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
                        return _buildImageGridItem(image);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGridItem(Map<String, dynamic> image) {
    final thumbnailUrl = image['thumbnail_url'] ?? image['piclink'];
    final fullUrl = image['large_url'] ?? image['piclink'];
    final hasNote =
        image['clinicalnote'] != null &&
        image['clinicalnote'].toString().isNotEmpty;

    // Parse date
    String dateStr = '';
    if (image['created_at'] != null) {
      try {
        final date = DateTime.parse(image['created_at'].toString()).toLocal();
        dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (e) {
        // ignore
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                  // Note Icon (Top Right)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _showNoteDialog(image),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          hasNote ? Icons.description : Icons.note_add_outlined,
                          color: hasNote ? Colors.blueAccent : Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  // Zoom Icon (Bottom Right)
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
          ),
        ),
        if (dateStr.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  void _showNoteDialog(Map<String, dynamic> image) {
    _noteController.text = image['clinicalnote'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clinical Note'),
        content: TextField(
          controller: _noteController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter doctor comments...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newNote = _noteController.text.trim();
              final success = await CloudinaryService.updateEcgClinicalNote(
                image['id'],
                newNote,
              );

              if (mounted) {
                Navigator.pop(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note saved successfully')),
                  );
                  // Update local state without full refresh
                  setState(() {
                    image['clinicalnote'] = newNote;
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to save note')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
