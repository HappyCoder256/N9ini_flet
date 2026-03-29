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

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    tz_data.initializeTimeZones();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('Initializing notification service...');

    // Android initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'default_category',
          actions: [
            DarwinNotificationAction.plain('view', 'View'),
            DarwinNotificationAction.plain(
              'dismiss',
              'Dismiss',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
              },
            ),
            DarwinNotificationAction.plain(
              'open',
              'Open',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );

    // macOS initialization
    final DarwinInitializationSettings initializationSettingsMacOS =
        DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'default_category',
          actions: [
            DarwinNotificationAction.plain('view', 'View'),
            DarwinNotificationAction.plain(
              'dismiss',
              'Dismiss',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
              },
            ),
            DarwinNotificationAction.plain(
              'open',
              'Open',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );

    // ✅ Windows initialization
    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
      appName: 'N9ini Flet App',
      appUserModelId: 'com.flet.app',
      guid: 'accf681e-5746-4435-8291-a7307d423319', // unique GUID for your app
    );

    // Combine all platform settings
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
      macOS: initializationSettingsMacOS,
      windows: initializationSettingsWindows, // ✅ added
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint(
            'Notification tapped: ${response.id}, ${response.payload}, ${response.actionId}');
        if (_onActionCallback != null) {
          _onActionCallback!(response.actionId ?? 'tap', response.payload ?? '');
        }
      },
    );

    _isInitialized = true;
    debugPrint('Notification service initialized successfully');
  }

  Function(String, String)? _onActionCallback;

  void setActionCallback(Function(String, String) callback) {
    _onActionCallback = callback;
  }

  // ✅ Build platform-specific notification details
  NotificationDetails _buildNotificationDetails(
      List<NotificationActionData>? actions) {
    // Android details
    AndroidNotificationDetails androidDetails;
    if (actions != null && actions.isNotEmpty) {
      List<AndroidNotificationAction> androidActions = actions
          .map((action) => AndroidNotificationAction(
                action.id,
                action.title,
                showsUserInterface: action.foreground,
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

    // iOS/macOS details
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: 'default_category',
    );

    // ✅ Windows details
    WindowsNotificationDetails windowsDetails = WindowsNotificationDetails(
      actions: actions != null && actions.isNotEmpty
          ? actions
              .map((action) => WindowsAction(
                    content: action.title,
                    arguments: action.id,
                  ))
              .toList()
          : [],
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      windows: windowsDetails, // ✅ added
    );
  }

  // Show a notification
  Future<void> showNotification(
    int id,
    String title,
    String body, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();

    final notificationDetails = _buildNotificationDetails(actions);

    try {
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      debugPrint('Notification shown successfully: ID=$id, Title=$title');
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  // Schedule a notification
  Future<void> scheduleNotification(
    int id,
    String title,
    String body,
    DateTime scheduledDate, {
    String? payload,
    List<NotificationActionData>? actions,
  }) async {
    if (!_isInitialized) await initialize();

    // ✅ Windows does not support zonedSchedule
    // use show() with a manual delay on Windows
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
        debugPrint(
            'Windows scheduled notification shown at: ${DateTime.now()}');
      });
      return;
    }

    final notificationDetails = _buildNotificationDetails(actions);

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      debugPrint(
          'Notification scheduled successfully for: ${scheduledDate.toString()}');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }

  // Request permissions
  Future<bool?> requestPermissions() async {
    if (!_isInitialized) await initialize();

    // ✅ Windows doesn't need permission requests
    if (Platform.isWindows) {
      debugPrint('Windows: no permission request needed');
      return true;
    }

    bool? androidResult;
    try {
      androidResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      debugPrint('Android permissions: $androidResult');
    } catch (e) {
      debugPrint('Error requesting Android permissions: $e');
    }

    bool? iosResult;
    try {
      iosResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      debugPrint('iOS permissions: $iosResult');
    } catch (e) {
      debugPrint('Error requesting iOS permissions: $e');
    }

    bool? macOSResult;
    try {
      macOSResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      debugPrint('macOS permissions: $macOSResult');
    } catch (e) {
      debugPrint('Error requesting macOS permissions: $e');
    }

    return macOSResult ?? iosResult ?? androidResult;
  }
}

// Notification action data class
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
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _subscribeMethods();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();

    _notificationService.setActionCallback((actionId, payload) {
      widget.backend.triggerControlEvent(
        widget.control.id,
        "notification_action",
        json.encode({"actionId": actionId, "payload": payload}),
      );
    });
  }

  void _subscribeMethods() {
    widget.backend.subscribeMethods(widget.control.id, _handleMethods);
  }

  List<NotificationActionData>? _parseActions(String? actionsStr) {
    if (actionsStr == null || actionsStr.isEmpty) return null;

    List<NotificationActionData> actions = [];
    List<String> actionItems = actionsStr.split(',');

    for (String actionItem in actionItems) {
      List<String> parts = actionItem.split('|');
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

  Future<String?> _handleMethods(
      String methodName, Map<String, String> args) async {
    debugPrint('Method called: $methodName with arguments: $args');

    switch (methodName) {
      case 'show_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        final title = args['title'] ?? '';
        final body = args['body'] ?? '';
        final payload = args['payload'];
        final actions = _parseActions(args['actions']);

        await _notificationService.showNotification(
          id,
          title,
          body,
          payload: payload,
          actions: actions,
        );
        return 'ok';

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
          await _notificationService.scheduleNotification(
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

      case 'request_permissions':
        final result = await _notificationService.requestPermissions();
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
