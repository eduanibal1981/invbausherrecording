import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Cloudinary configuration for doppler images
class CloudinaryConfig {
  static const String cloudName = 'dgz3qiyg5';
  static const String uploadPreset =
      'doppler_upload'; // You may need to create this in Cloudinary
  static const String apiKey = '982848555897168';
  static const String apiSecret = 'hgcBanC0iIISNwkw-16r_QjG8bI';
  static const String supabaseUrl = 'https://gyshsorklnpudckucpva.supabase.co';
  static const String supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5c2hzb3JrbG5wdWRja3VjcHZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDA4Njk0MDksImV4cCI6MjA1NjQ0NTQwOX0.tb3BucsaN3u8DGfDOYjb4mNygyHGhb21_CWX_SLAM9w';
}

/// Result from Cloudinary upload
class CloudinaryUploadResult {
  final bool success;
  final String? message;
  final String? thumbnailUrl;
  final String? mediumUrl;
  final String? largeUrl;
  final String? fullUrl;
  final bool alreadyExists;

  CloudinaryUploadResult({
    required this.success,
    this.message,
    this.thumbnailUrl,
    this.mediumUrl,
    this.largeUrl,
    this.fullUrl,
    this.alreadyExists = false,
  });
}

class CloudinaryDeleteResult {
  final bool success;
  final String? message;

  CloudinaryDeleteResult({required this.success, this.message});
}

/// Service for uploading images to Cloudinary and saving to Supabase
class CloudinaryService {
  /// Upload image to Cloudinary with optimization and save URLs to Supabase
  static Future<CloudinaryUploadResult> uploadDopplerImage({
    required List<int> imageBytes,
    required String pcid,
  }) async {
    try {
      // Step 1: Validate image
      if (imageBytes.isEmpty) {
        return CloudinaryUploadResult(
          success: false,
          message: 'Image bytes are empty',
        );
      }

      // Step 2: Convert to base64
      String base64Image = base64Encode(imageBytes);
      String base64String = 'data:image/jpeg;base64,$base64Image';

      // Step 3: Upload to Cloudinary
      final cloudinaryUrl = Uri.parse(
        'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/image/upload',
      );

      final cloudinaryResponse = await http.post(
        cloudinaryUrl,
        body: {
          'file': base64String,
          'upload_preset': CloudinaryConfig.uploadPreset,
          'folder': 'doppler/$pcid',
          'public_id': 'doppler_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      // Step 4: Handle Cloudinary errors
      if (cloudinaryResponse.statusCode != 200) {
        final errorBody =
            _tryDecodeErrorMessage(cloudinaryResponse.body) ??
            cloudinaryResponse.body;
        return CloudinaryUploadResult(
          success: false,
          message:
              'Cloudinary upload failed: ${cloudinaryResponse.statusCode} - $errorBody',
        );
      }

      final cloudinaryResult = json.decode(cloudinaryResponse.body);
      final publicId = cloudinaryResult['public_id'];

      // Step 5: Generate optimized URLs for different use cases
      final cloudName = CloudinaryConfig.cloudName;

      // Thumbnail: 200x200, optimized for list views
      String thumbnailUrl =
          'https://res.cloudinary.com/$cloudName/image/upload/w_200,h_200,c_fill,q_auto,f_auto/$publicId.jpg';

      // Medium: 800x800, optimized for detail views
      String mediumUrl =
          'https://res.cloudinary.com/$cloudName/image/upload/w_800,h_800,c_limit,q_auto,f_auto/$publicId.jpg';

      // Large: 1200x1200, for full screen views
      String largeUrl =
          'https://res.cloudinary.com/$cloudName/image/upload/w_1200,h_1200,c_limit,q_auto,f_auto/$publicId.jpg';

      // Original: Full size with auto quality and format optimization
      String fullUrl =
          'https://res.cloudinary.com/$cloudName/image/upload/q_auto,f_auto/$publicId.jpg';

      // Step 6: Check if already in Supabase
      final checkUrl = Uri.parse(
        '${CloudinaryConfig.supabaseUrl}/rest/v1/doppplerslinks?pcid=eq.$pcid&thumbnail_url=eq.${Uri.encodeComponent(thumbnailUrl)}',
      );

      final checkResponse = await http.get(
        checkUrl,
        headers: {
          'apikey': CloudinaryConfig.supabaseKey,
          'Authorization': 'Bearer ${CloudinaryConfig.supabaseKey}',
        },
      );

      final existing = json.decode(checkResponse.body);
      if (existing.length > 0) {
        return CloudinaryUploadResult(
          success: true,
          message: 'Image uploaded (already in database)',
          thumbnailUrl: thumbnailUrl,
          mediumUrl: mediumUrl,
          largeUrl: largeUrl,
          fullUrl: fullUrl,
          alreadyExists: true,
        );
      }

      // Step 7: Save all URLs to Supabase
      final supabasePostUrl = Uri.parse(
        '${CloudinaryConfig.supabaseUrl}/rest/v1/doppplerslinks',
      );

      final supabaseResponse = await http.post(
        supabasePostUrl,
        headers: {
          'apikey': CloudinaryConfig.supabaseKey,
          'Authorization': 'Bearer ${CloudinaryConfig.supabaseKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        body: json.encode({
          'pcid': pcid,
          'piclink': mediumUrl, // Keep for backward compatibility
          'thumbnail_url': thumbnailUrl,
          'medium_url': mediumUrl,
          'large_url': largeUrl,
          'full_url': fullUrl,
        }),
      );

      // Step 8: Handle Supabase response
      if (supabaseResponse.statusCode == 201 ||
          supabaseResponse.statusCode == 200) {
        return CloudinaryUploadResult(
          success: true,
          message: 'Image uploaded and saved successfully',
          thumbnailUrl: thumbnailUrl,
          mediumUrl: mediumUrl,
          largeUrl: largeUrl,
          fullUrl: fullUrl,
          alreadyExists: false,
        );
      } else {
        final errorBody =
            _tryDecodeErrorMessage(supabaseResponse.body) ??
            supabaseResponse.body;
        return CloudinaryUploadResult(
          success: true,
          message:
              'Uploaded to Cloudinary but failed to save to Supabase: ${supabaseResponse.statusCode} - $errorBody',
          thumbnailUrl: thumbnailUrl,
          mediumUrl: mediumUrl,
          largeUrl: largeUrl,
          fullUrl: fullUrl,
        );
      }
    } catch (e) {
      return CloudinaryUploadResult(
        success: false,
        message: 'Exception: ${e.toString()}',
      );
    }
  }

  static String? _tryDecodeErrorMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] != null) {
          return error['message'].toString();
        }
        if (decoded['message'] != null) {
          return decoded['message'].toString();
        }
        if (decoded['error_description'] != null) {
          return decoded['error_description'].toString();
        }
        if (decoded['details'] != null) {
          return decoded['details'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Delete a doppler image from Cloudinary and remove the record in Supabase
  static Future<CloudinaryDeleteResult> deleteDopplerImage(
    Map<String, dynamic> image,
  ) async {
    try {
      final idValue = image['id'];
      final id = idValue is int ? idValue : int.tryParse(idValue.toString());
      if (id == null) {
        return CloudinaryDeleteResult(
          success: false,
          message: 'Missing image id for deletion',
        );
      }

      final publicId = _extractPublicIdFromImage(image);
      if (publicId == null || publicId.isEmpty) {
        return CloudinaryDeleteResult(
          success: false,
          message: 'Unable to determine Cloudinary public id',
        );
      }

      final cloudinaryResult = await _deleteFromCloudinary(publicId);
      if (!cloudinaryResult.success) {
        return cloudinaryResult;
      }

      final supabaseResult = await _deleteFromSupabase(id);
      if (!supabaseResult.success) {
        return CloudinaryDeleteResult(
          success: false,
          message:
              'Deleted from Cloudinary but failed to remove from Supabase: ${supabaseResult.message ?? 'Unknown error'}',
        );
      }

      return CloudinaryDeleteResult(
        success: true,
        message: 'Image deleted from Cloudinary and Supabase',
      );
    } catch (e) {
      return CloudinaryDeleteResult(
        success: false,
        message: 'Exception: ${e.toString()}',
      );
    }
  }

  /// Fetch all doppler images for a patient from Supabase
  static Future<List<Map<String, dynamic>>> fetchDopplerImages(
    String pcid,
  ) async {
    try {
      final url = Uri.parse(
        '${CloudinaryConfig.supabaseUrl}/rest/v1/doppplerslinks?pcid=eq.$pcid&order=created_at.desc',
      );

      final response = await http.get(
        url,
        headers: {
          'apikey': CloudinaryConfig.supabaseKey,
          'Authorization': 'Bearer ${CloudinaryConfig.supabaseKey}',
        },
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<CloudinaryDeleteResult> _deleteFromSupabase(int id) async {
    try {
      final url = Uri.parse(
        '${CloudinaryConfig.supabaseUrl}/rest/v1/doppplerslinks?id=eq.$id',
      );

      final response = await http.delete(
        url,
        headers: {
          'apikey': CloudinaryConfig.supabaseKey,
          'Authorization': 'Bearer ${CloudinaryConfig.supabaseKey}',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        return CloudinaryDeleteResult(success: true);
      }
      final errorBody =
          _tryDecodeErrorMessage(response.body) ?? response.body;
      return CloudinaryDeleteResult(
        success: false,
        message: '${response.statusCode} - $errorBody',
      );
    } catch (e) {
      return CloudinaryDeleteResult(
        success: false,
        message: 'Exception: ${e.toString()}',
      );
    }
  }

  static Future<CloudinaryDeleteResult> _deleteFromCloudinary(
    String publicId,
  ) async {
    if (CloudinaryConfig.apiKey.isEmpty ||
        CloudinaryConfig.apiSecret.isEmpty) {
      return CloudinaryDeleteResult(
        success: false,
        message:
            'Cloudinary API credentials missing. Set --dart-define=CLOUDINARY_API_KEY=... and --dart-define=CLOUDINARY_API_SECRET=...',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signaturePayload =
        '${_buildSignaturePayload({
          'invalidate': 'true',
          'public_id': publicId,
          'timestamp': timestamp.toString(),
        })}${CloudinaryConfig.apiSecret}';
    final signature =
        sha1.convert(utf8.encode(signaturePayload)).toString();

    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/image/destroy',
    );

    final response = await http.post(
      url,
      body: {
        'public_id': publicId,
        'timestamp': timestamp.toString(),
        'api_key': CloudinaryConfig.apiKey,
        'signature': signature,
        'invalidate': 'true',
      },
    );

    if (response.statusCode != 200) {
      final errorBody =
          _tryDecodeErrorMessage(response.body) ?? response.body;
      return CloudinaryDeleteResult(
        success: false,
        message: '${response.statusCode} - $errorBody',
      );
    }

    final decoded = json.decode(response.body);
    final result = decoded is Map<String, dynamic> ? decoded['result'] : null;
    if (result == 'ok' || result == 'not found') {
      return CloudinaryDeleteResult(success: true);
    }

    return CloudinaryDeleteResult(
      success: false,
      message: decoded.toString(),
    );
  }

  static String? _extractPublicIdFromImage(Map<String, dynamic> image) {
    final candidates = [
      image['full_url'],
      image['large_url'],
      image['medium_url'],
      image['thumbnail_url'],
      image['piclink'],
    ];

    for (final candidate in candidates) {
      final url = candidate?.toString();
      final publicId = _extractPublicIdFromUrl(url);
      if (publicId != null && publicId.isNotEmpty) {
        return publicId;
      }
    }
    return null;
  }

  static String? _extractPublicIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final uploadIndex = segments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 1 >= segments.length) {
        return null;
      }

      var index = uploadIndex + 1;
      while (index < segments.length &&
          _looksLikeTransformationSegment(segments[index])) {
        index++;
      }

      if (index >= segments.length) return null;
      final idSegments = segments.sublist(index);
      if (idSegments.isEmpty) return null;

      final last = idSegments.last;
      final dotIndex = last.lastIndexOf('.');
      final lastSegment =
          dotIndex == -1 ? last : last.substring(0, dotIndex);

      final fullSegments = [...idSegments];
      fullSegments[fullSegments.length - 1] = lastSegment;
      return fullSegments.join('/');
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeTransformationSegment(String segment) {
    if (RegExp(r'^v\d+$').hasMatch(segment)) {
      return true;
    }
    final transformPattern = RegExp(
      r'^(?:[a-z]{1,3}_[^/]+)(?:,[a-z]{1,3}_[^/]+)*$',
    );
    return transformPattern.hasMatch(segment);
  }

  static String _buildSignaturePayload(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    return keys.map((key) => '$key=${params[key]}').join('&');
  }
}
