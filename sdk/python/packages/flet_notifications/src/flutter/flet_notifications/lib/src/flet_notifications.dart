import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'dart:convert';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  Function(String, String)? _onActionCallback;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    tz_data.initializeTimeZones();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint('Initializing notification service...');

    // Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'default_category',
          actions: [
            DarwinNotificationAction.plain('view', 'View'),
            DarwinNotificationAction.plain(
              'dismiss',
              'Dismiss',
              options: {DarwinNotificationActionOption.destructive},
            ),
            DarwinNotificationAction.plain(
              'open',
              'Open',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );

    // macOS
    final DarwinInitializationSettings macOSSettings =
        DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'default_category',
          actions: [
            DarwinNotificationAction.plain('view', 'View'),
            DarwinNotificationAction.plain(
              'dismiss',
              'Dismiss',
              options: {DarwinNotificationActionOption.destructive},
            ),
            DarwinNotificationAction.plain(
              'open',
              'Open',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );

    // Windows
    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
      appName: 'Flet App',
      appUserModelId: 'com.flet.app',
      guid: 'd49a6d89-2d4a-4a2a-a8f2-1234567890ab',
    );

    // Combine
    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macOSSettings,
      windows: windowsSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint(
            'Notification response: id=${response.id}, '
            'payload=${response.payload}, action=${response.actionId}');
        if (_onActionCallback != null) {
          _onActionCallback!(
            response.actionId ?? 'tap',
            response.payload ?? '',
          );
        }
      },
    );

    _isInitialized = true;
    debugPrint('Notification service initialized successfully');
  }

  void setActionCallback(Function(String, String) callback) {
    _onActionCallback = callback;
  }

  // -----------------------------------------------------------------------
  // Build notification details
  // -----------------------------------------------------------------------

  NotificationDetails _buildDetails(List<NotificationActionData>? actions) {
    // --- Android ---
    AndroidNotificationDetails androidDetails;
    if (actions != null && actions.isNotEmpty) {
      final androidActions = actions
          .map((a) => AndroidNotificationAction(
                a.id,
                a.title,
                showsUserInterface: a.foreground,
              ))
          .toList();
      androidDetails = AndroidNotificationDetails(
        'your_channel_id',
        'your_channel_name',
        channelDescription: 'your_channel_description',
        importance: Importance.max,
        priority: Priority.high,
        actions: androidActions,
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        'your_channel_id',
        'your_channel_name',
        channelDescription: 'your_channel_description',
        importance: Importance.max,
        priority: Priority.high,
      );
    }

    // --- iOS / macOS ---
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'default_category',
    );

    // --- Windows ---
    final WindowsNotificationDetails windowsDetails = WindowsNotificationDetails(
      actions: actions != null && actions.isNotEmpty
          ? actions
              .map((a) => WindowsAction(
                    content: a.title,
                    arguments: a.id,
                  ))
              .toList()
          : [],
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails,
    );
  }

  // -----------------------------------------------------------------------
  // Show notification
  // -----------------------------------------------------------------------

  Future<void> showNotification(
    int id,
    String title,
    String body, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        _buildDetails(actions),
        payload: payload,
      );
      debugPrint('Notification shown: ID=$id, Title=$title');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Schedule notification
  // -----------------------------------------------------------------------

  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();

    // Windows does not support zonedSchedule — use Future.delayed instead
    if (Platform.isWindows) {
      final delay = scheduledDate.difference(DateTime.now());
      if (delay.isNegative) {
        debugPrint('Scheduled date is in the past, showing immediately');
        await showNotification(id, title, body,
            payload: payload, actions: actions);
        return;
      }
      Future.delayed(delay, () async {
        await showNotification(id, title, body,
            payload: payload, actions: actions);
        debugPrint('Windows scheduled notification shown at: ${DateTime.now()}');
      });
      return;
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        _buildDetails(actions),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      debugPrint('Notification scheduled for: $scheduledDate');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Cancel notification
  // -----------------------------------------------------------------------

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
      debugPrint('Notification cancelled: ID=$id');
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Request permissions
  // -----------------------------------------------------------------------

  Future<bool?> requestPermissions() async {
    if (!_isInitialized) await initialize();
  
    if (Platform.isWindows) {
      debugPrint('Windows: no permission request needed');
      return true;
    }
  
    if (Platform.isAndroid) {
      bool? result;
      try {
        final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
            flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation
                    AndroidFlutterLocalNotificationsPlugin>();
        result = await androidPlugin?.requestNotificationsPermission();
        debugPrint('Android permissions: $result');
      } catch (e) {
        debugPrint('Error requesting Android permissions: $e');
      }
      return result;
    }
  
    if (Platform.isIOS) {
      bool? result;
      try {
        final IOSFlutterLocalNotificationsPlugin? iosPlugin =
            flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation
                    IOSFlutterLocalNotificationsPlugin>();
        result = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('iOS permissions: $result');
      } catch (e) {
        debugPrint('Error requesting iOS permissions: $e');
      }
      return result;
    }
  
    if (Platform.isMacOS) {
      bool? result;
      try {
        final MacOSFlutterLocalNotificationsPlugin? macOSPlugin =
            flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation
                    MacOSFlutterLocalNotificationsPlugin>();
        result = await macOSPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('macOS permissions: $result');
      } catch (e) {
        debugPrint('Error requesting macOS permissions: $e');
      }
      return result;
    }
  
    return false;
  }

// -----------------------------------------------------------------------
// Notification action data
// -----------------------------------------------------------------------

class NotificationActionData {
  final String id;
  final String title;
  final bool destructive;
  final bool foreground;

  NotificationActionData({
    required this.id,
    required this.title,
    this.destructive = false,
    this.foreground = true,
  });
}

// -----------------------------------------------------------------------
// Flet control widget
// -----------------------------------------------------------------------

class FletNotificationsControl extends StatefulWidget {
  final Control? parent;
  final Control control;
  final List<Control> children;
  final FletControlBackend backend;

  const FletNotificationsControl({
    Key? key,
    required this.parent,
    required this.control,
    required this.children,
    required this.backend,
  }) : super(key: key);

  @override
  State<FletNotificationsControl> createState() =>
      _FletNotificationsControlState();
}

class _FletNotificationsControlState extends State<FletNotificationsControl> {
  final NotificationService _service = NotificationService();

  @override
  void initState() {
    super.initState();
    _initialize();
    _subscribeMethods();
  }

  Future<void> _initialize() async {
    await _service.initialize();
    _service.setActionCallback((actionId, payload) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        'notification_action',
        json.encode({'actionId': actionId, 'payload': payload}),
      );
    });
  }

  void _subscribeMethods() {
    widget.backend.subscribeMethods(widget.control.id, _handleMethod);
  }

  List<NotificationActionData>? _parseActions(String? actionsStr) {
    if (actionsStr == null || actionsStr.isEmpty) return null;

    final List<NotificationActionData> actions = [];
    for (final item in actionsStr.split(',')) {
      final parts = item.split('|');
      if (parts.length >= 2) {
        actions.add(NotificationActionData(
          id: parts[0],
          title: parts[1],
          destructive: parts.length > 2 ? parts[2] == 'true' : false,
          foreground: parts.length > 3 ? parts[3] == 'true' : true,
        ));
      }
    }

    return actions.isNotEmpty ? actions : null;
  }

  Future<String?> _handleMethod(
      String methodName, Map<String, String> args) async {
    debugPrint('Notification method: $methodName args: $args');

    switch (methodName) {
      // --- show_notification ---
      case 'show_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        final title = args['title'] ?? '';
        final body = args['body'] ?? '';
        final payload = args['payload'];
        final actions = _parseActions(args['actions']);
        await _service.showNotification(
          id,
          title,
          body,
          payload: payload,
          actions: actions,
        );
        return 'ok';

      // --- schedule_notification ---
      case 'schedule_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        final title = args['title'] ?? '';
        final body = args['body'] ?? '';
        final payload = args['payload'];
        final dateTimeStr = args['scheduled_date'] ?? '';
        final actions = _parseActions(args['actions']);

        if (dateTimeStr.isEmpty) return 'error:missing_date';

        try {
          final scheduledDate = DateTime.parse(dateTimeStr);
          await _service.scheduleNotification(
            id,
            title,
            body,
            scheduledDate,
            payload: payload,
            actions: actions,
          );
          return 'ok';
        } catch (e) {
          debugPrint('Error parsing date: $e');
          return 'error:invalid_date';
        }

      // --- cancel_notification ---
      case 'cancel_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        await _service.cancelNotification(id);
        return 'ok';

      // --- cancel_all_notifications ---
      case 'cancel_all_notifications':
        await _service.cancelAllNotifications();
        return 'ok';

      // --- request_permissions ---
      case 'request_permissions':
        final result = await _service.requestPermissions();
        return result.toString();

      default:
        debugPrint('Unrecognized method: $methodName');
        return null;
    }
  }

  @override
  void dispose() {
    widget.backend.unsubscribeMethods(widget.control.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
