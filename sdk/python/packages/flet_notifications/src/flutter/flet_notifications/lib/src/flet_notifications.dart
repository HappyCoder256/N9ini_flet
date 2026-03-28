import 'package:flet/flet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    // Initialize timezone data
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
                DarwinNotificationAction.plain(
                  'view', 
                  'View',
                ),
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
                DarwinNotificationAction.plain(
                  'view', 
                  'View',
                ),
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
    
    // Combine settings
    final InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
        macOS: initializationSettingsMacOS);
    
    // Initialize plugin
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.id}, ${response.payload}, ${response.actionId}');
        // Handle notification response
        if (_onActionCallback != null) {
          _onActionCallback!(response.actionId ?? 'tap', response.payload ?? '');
        }
      },
    );
    
    _isInitialized = true;
    debugPrint('Notification service initialized successfully');
  }

  // Callback for notification actions
  Function(String, String)? _onActionCallback;

  void setActionCallback(Function(String, String) callback) {
    _onActionCallback = callback;
  }

  // Show a notification with actions
  Future<void> showNotification(
    int id, 
    String title, 
    String body, 
    {String? payload, List<NotificationActionData>? actions}
  ) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Android details
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    // Add actions to Android notification if provided
    if (actions != null && actions.isNotEmpty) {
      List<AndroidNotificationAction> androidActions = actions.map((action) => 
        AndroidNotificationAction(
          action.id, 
          action.title,
          showsUserInterface: action.foreground,
        )
      ).toList();
      
      androidDetails = AndroidNotificationDetails(
        'your_channel_id',
        'your_channel_name',
        channelDescription: 'your_channel_description',
        importance: Importance.max,
        priority: Priority.high,
        actions: androidActions,
      );
    }
    
    // iOS/macOS details
    DarwinNotificationDetails darwinDetails = const DarwinNotificationDetails(
      categoryIdentifier: 'default_category',
    );
    
    // Combine details
    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    
    // Show notification
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
    DateTime scheduledDate,
    {String? payload, List<NotificationActionData>? actions}
  ) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Android details
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    // Add actions to Android notification if provided
    if (actions != null && actions.isNotEmpty) {
      List<AndroidNotificationAction> androidActions = actions.map((action) => 
        AndroidNotificationAction(
          action.id, 
          action.title,
          showsUserInterface: action.foreground,
        )
      ).toList();
      
      androidDetails = AndroidNotificationDetails(
        'your_channel_id',
        'your_channel_name',
        channelDescription: 'your_channel_description',
        importance: Importance.max,
        priority: Priority.high,
        actions: androidActions,
      );
    }
    
    // iOS/macOS details
    DarwinNotificationDetails darwinDetails = const DarwinNotificationDetails(
      categoryIdentifier: 'default_category',
    );
    
    // Combine details
    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    
    // Schedule notification
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
      debugPrint('Notification scheduled successfully for: ${scheduledDate.toString()}');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }
  
  // Request permissions
  Future<bool?> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Android
    bool? androidResult;
    try {
      androidResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      debugPrint('Android permissions: $androidResult');
    } catch (e) {
      debugPrint('Error requesting Android permissions: $e');
    }
    
    // iOS
    bool? iosResult;
    try {
      iosResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      debugPrint('iOS permissions: $iosResult');
    } catch (e) {
      debugPrint('Error requesting iOS permissions: $e');
    }
    
    // macOS
    bool? macOSResult;
    try {
      macOSResult = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      debugPrint('macOS permissions: $macOSResult');
    } catch (e) {
      debugPrint('Error requesting macOS permissions: $e');
    }
    
    return macOSResult ?? iosResult ?? androidResult;
  }
}

// Class to represent notification action data
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
  State<FletNotificationsControl> createState() => _FletNotificationsControlState();
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
      // Forward the action to Python side
      widget.backend.triggerControlEvent(
        widget.control.id, 
        "notification_action",
        json.encode({"actionId": actionId, "payload": payload})
      );
    });
  }

  void _subscribeMethods() {
    widget.backend.subscribeMethods(widget.control.id, _handleMethods);
  }

  // Parse actions from string format
  List<NotificationActionData>? _parseActions(String? actionsStr) {
    if (actionsStr == null || actionsStr.isEmpty) {
      return null;
    }
    
    List<NotificationActionData> actions = [];
    List<String> actionItems = actionsStr.split(',');
    
    for (String actionItem in actionItems) {
      List<String> parts = actionItem.split('|');
      if (parts.length >= 2) {
        String id = parts[0];
        String title = parts[1];
        bool destructive = parts.length > 2 ? parts[2] == 'true' : false;
        bool foreground = parts.length > 3 ? parts[3] == 'true' : true;
        
        actions.add(NotificationActionData(
          id: id,
          title: title,
          destructive: destructive,
          foreground: foreground,
        ));
      }
    }
    
    return actions.isNotEmpty ? actions : null;
  }

  Future<String?> _handleMethods(String methodName, Map<String, String> args) async {
    debugPrint('Method called: $methodName with arguments: $args');
    
    switch (methodName) {
      case 'show_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        final title = args['title'] ?? '';
        final body = args['body'] ?? '';
        final payload = args['payload'];
        final actionsStr = args['actions'];
        
        final actions = _parseActions(actionsStr);
        
        await _notificationService.showNotification(
          id, 
          title, 
          body, 
          payload: payload,
          actions: actions
        );
        return 'ok';
      
      case 'schedule_notification':
        final id = int.tryParse(args['id'] ?? '0') ?? 0;
        final title = args['title'] ?? '';
        final body = args['body'] ?? '';
        final payload = args['payload'];
        final dateTimeStr = args['scheduled_date'] ?? '';
        final actionsStr = args['actions'];
        
        if (dateTimeStr.isEmpty) {
          return 'error:missing_date';
        }
        
        try {
          final scheduledDate = DateTime.parse(dateTimeStr);
          final actions = _parseActions(actionsStr);
          
          await _notificationService.scheduleNotification(
            id, 
            title, 
            body, 
            scheduledDate, 
            payload: payload,
            actions: actions
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
    // Non-visual control
    return const SizedBox.shrink();
  }
}