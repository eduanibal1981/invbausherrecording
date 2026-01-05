import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `Firebase.initializeApp` before using other Firebase services.
  debugPrint('Handling a background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // 1. Request Permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
    } else {
      debugPrint('User declined or has not accepted permission');
      return;
    }

    // 2. Setup Local Notifications (for foreground)
    // Ensure you have a drawable named 'ic_launcher' in 'android/app/src/main/res/drawable/'.
    // Or use '@mipmap/ic_launcher' provided it exists.
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        debugPrint('Notification tapped with payload: ${response.payload}');
      },
    );

    // 3. Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
          'Message also contained a notification: ${message.notification}',
        );
        _showLocalNotification(message);
      }
    });

    // 4. Background Message Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 5. Get Token and Upload
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        await saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('Error fetching FCM token: $e');
    }

    // 6. Token Refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      saveTokenToSupabase(newToken);
    });
  }

  Future<void> saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // NOTE: This assumes you have a column 'fcm_token' in your 'staff' table.
      // If not, you must create it in your Supabase dashboard.
      await Supabase.instance.client
          .from('staff')
          .update({'fcm_token': token})
          .eq('userid', user.id);

      debugPrint('FCM Token saved to Supabase');
    } catch (e) {
      debugPrint('Error saving FCM token to Supabase: $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // id
            'High Importance Notifications', // title
            channelDescription:
                'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  }

  /// Get the current device's FCM token (useful for testing)
  Future<String?> getDeviceToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Send a push notification via Supabase Edge Function
  ///
  /// Example usage:
  /// ```dart
  /// await NotificationService().sendPushNotification(
  ///   token: 'fcm_device_token_here',
  ///   title: 'New Blood Test Result',
  ///   body: 'Your patient has new lab results available.',
  /// );
  /// ```
  Future<Map<String, dynamic>> sendPushNotification({
    required String token,
    required String title,
    required String body,
    String? userId,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'push-notification',
        body: {
          'token': token,
          'title': title,
          'body': body,
          if (userId != null) 'user_id': userId,
        },
      );

      if (response.status == 200) {
        debugPrint('Push notification sent successfully: ${response.data}');
        return {'success': true, 'data': response.data};
      } else {
        debugPrint('Push notification failed: ${response.data}');
        return {'success': false, 'error': response.data};
      }
    } catch (e) {
      debugPrint('Error sending push notification: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send push notification to a user by fetching their token from the database
  Future<Map<String, dynamic>> sendPushNotificationToUser({
    required String staffUserId,
    required String title,
    required String body,
  }) async {
    try {
      // Fetch the FCM token from the staff table
      final result = await Supabase.instance.client
          .from('staff')
          .select('fcm_token')
          .eq('userid', staffUserId)
          .maybeSingle();

      if (result == null || result['fcm_token'] == null) {
        return {'success': false, 'error': 'User has no FCM token registered'};
      }

      return await sendPushNotification(
        token: result['fcm_token'],
        title: title,
        body: body,
        userId: staffUserId,
      );
    } catch (e) {
      debugPrint('Error sending push notification to user: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
