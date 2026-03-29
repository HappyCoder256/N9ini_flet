import 'dart:convert';
import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// ============================================================
// NotificationActionData
// ============================================================

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

// ============================================================
// NotificationService
// ============================================================

class NotificationService {
  static final NotificationService _instance =
      NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal() {
    tz_data.initializeTimeZones();
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Function(String, String)? _onActionCallback;

  void setActionCallback(Function(String, String) callback) {
    _onActionCallback = callback;
  }

  // ----------------------------------------------------------
  // Initialize
  // ----------------------------------------------------------

  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint('Initializing notification service...');

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
      appName: 'Flet App',
      appUserModelId: 'com.flet.app',
      guid: 'd49a6d89-2d4a-4a2a-a8f2-1234567890ab',
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macOSSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
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
    debugPrint('Notification service initialized');
  }

  // ----------------------------------------------------------
  // Build notification details
  // ----------------------------------------------------------

  NotificationDetails _buildDetails(
      List<NotificationActionData>? actions) {
    // Android
    AndroidNotificationDetails androidDetails;
    if (actions != null && actions.isNotEmpty) {
      final List<AndroidNotificationAction> androidActions = actions
          .map((NotificationActionData a) => AndroidNotificationAction(
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

    // iOS / macOS
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'default_category',
    );

    // Windows
    final List<WindowsAction> windowsActions = actions != null
        ? actions
            .map((NotificationActionData a) => WindowsAction(
                  content: a.title,
                  arguments: a.id,
                ))
            .toList()
        : [];

    final WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails(actions: windowsActions);

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails,
    );
  }

  // ----------------------------------------------------------
  // Show notification
  // ----------------------------------------------------------

  Future<void> showNotification(
    int id,
    String title,
    String body, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();
    try {
      await _plugin.show(
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

  // ----------------------------------------------------------
  // Schedule notification
  // ----------------------------------------------------------

  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();

    if (Platform.isWindows) {
      final Duration delay = scheduledDate.difference(DateTime.now());
      if (delay.isNegative) {
        debugPrint('Scheduled date is in the past, showing immediately');
        await showNotification(id, title, body,
            payload: payload, actions: actions);
        return;
      }
      Future.delayed(delay, () async {
        await showNotification(id, title, body,
            payload: payload, actions: actions);
        debugPrint('Windows scheduled notification shown');
      });
      return;
    }

    try {
      await _plugin.zonedSchedule(
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

  // ----------------------------------------------------------
  // Cancel
  // ----------------------------------------------------------

  Future<void> cancelNotification(int id) async {
    try {
      await _plugin.cancel(id);
      debugPrint('Notification cancelled: ID=$id');
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    try {
      await _plugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }

  // ----------------------------------------------------------
  // Request permissions
  // ----------------------------------------------------------

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
            _plugin.resolvePlatformSpecificImplementation
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
            _plugin.resolvePlatformSpecificImplementation
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
            _plugin.resolvePlatformSpecificImplementation
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
}

// ============================================================
// FletNotificationsControl
// ============================================================

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

class _FletNotificationsControlState
    extends State<FletNotificationsControl> {
  final NotificationService _service = NotificationService();

  @override
  void initState() {
    super.initState();
    _initialize();
    _subscribeMethods();
  }

  Future<void> _initialize() async {
    await _service.initialize();
    _service.setActionCallback((String actionId, String payload) {
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
    for (final String item in actionsStr.split(',')) {
      final List<String> parts = item.split('|');
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
      case 'show_notification':
        final int id = int.tryParse(args['id'] ?? '0') ?? 0;
        final String title = args['title'] ?? '';
        final String body = args['body'] ?? '';
        final String? payload = args['payload'];
        final List<NotificationActionData>? actions =
            _parseActions(args['actions']);
        await _service.showNotification(
          id,
          title,
          body,
          payload: payload,
          actions: actions,
        );
        return 'ok';

      case 'schedule_notification':
        final int id = int.tryParse(args['id'] ?? '0') ?? 0;
        final String title = args['title'] ?? '';
        final String body = args['body'] ?? '';
        final String? payload = args['payload'];
        final String dateTimeStr = args['scheduled_date'] ?? '';
        final List<NotificationActionData>? actions =
            _parseActions(args['actions']);

        if (dateTimeStr.isEmpty) return 'error:missing_date';

        try {
          final DateTime scheduledDate = DateTime.parse(dateTimeStr);
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

      case 'cancel_notification':
        final int id = int.tryParse(args['id'] ?? '0') ?? 0;
        await _service.cancelNotification(id);
        return 'ok';

      case 'cancel_all_notifications':
        await _service.cancelAllNotifications();
        return 'ok';

      case 'request_permissions':
        final bool? result = await _service.requestPermissions();
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
