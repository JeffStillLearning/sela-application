import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// StreamController untuk komunikasi data dari foreground task ke UI.
/// Ini lebih reliable daripada callback langsung.
final _taskDataStreamController = StreamController<Object>.broadcast();

/// Stream untuk menerima data dari foreground task.
Stream<Object> get taskDataStream => _taskDataStreamController.stream;

/// Callback function for foreground task.
/// This must be a top-level function or static method.
/// DO NOT CHANGE THE FUNCTION SIGNATURE - required by flutter_foreground_task.
@pragma('vm:entry-point')
void startCallback() {
  debugPrint('[MonitoringService] ✓ startCallback invoked in isolate');
  debugPrint('[MonitoringService] ✓ Creating and registering TaskHandler');

  final handler = MyForegroundTaskHandler();
  FlutterForegroundTask.setTaskHandler(handler);

  debugPrint('[MonitoringService] ✓ TaskHandler registered successfully');
  debugPrint('[MonitoringService] ✓ onRepeatEvent will be called every 1 second');
}

/// Foreground task handler that executes every 1 second.
///
/// This class handles all foreground task lifecycle events.
class MyForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('╔═══════════════════════════════════════════════════════════');
    debugPrint('[MyForegroundTaskHandler] ✓ onStart called');
    debugPrint('[MyForegroundTaskHandler]   Timestamp: $timestamp');
    debugPrint('[MyForegroundTaskHandler]   TaskStarter: ${starter.name}');

    try {
      // Send initial data to UI to confirm service started
      final initData = <String, dynamic>{
        'type': 'service_started',
        'timestamp': timestamp.millisecondsSinceEpoch,
        'iso8601': timestamp.toIso8601String(),
        'starter': starter.name,
      };

      FlutterForegroundTask.sendDataToMain(initData);
      debugPrint('[MyForegroundTaskHandler] ✓ Initial data sent to UI: $initData');
    } catch (e, stackTrace) {
      debugPrint('[MyForegroundTaskHandler] ✗ Error sending initial data: $e');
      debugPrint('[MyForegroundTaskHandler]   Stack: $stackTrace');
    }

    debugPrint('╚═══════════════════════════════════════════════════════════');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is the critical method - called every 1 second based on eventAction
    debugPrint('┌───────────────────────────────────────────────────────────');
    debugPrint('[MyForegroundTaskHandler] ✓ onRepeatEvent EXECUTED');
    debugPrint('[MyForegroundTaskHandler]   Timestamp: $timestamp');
    debugPrint('[MyForegroundTaskHandler]   Milliseconds: ${timestamp.millisecondsSinceEpoch}');

    try {
      // Send data to UI every second
      final tickData = <String, dynamic>{
        'type': 'tick',
        'timestamp': timestamp.millisecondsSinceEpoch,
        'iso8601': timestamp.toIso8601String(),
        'second': timestamp.second,
      };

      FlutterForegroundTask.sendDataToMain(tickData);
      debugPrint('[MyForegroundTaskHandler] ✓ Data sent to UI: tick at ${timestamp.millisecondsSinceEpoch}');
    } catch (e, stackTrace) {
      debugPrint('[MyForegroundTaskHandler] ✗ Error sending data: $e');
      debugPrint('[MyForegroundTaskHandler]   Stack: $stackTrace');
    }

    debugPrint('└───────────────────────────────────────────────────────────');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('╔═══════════════════════════════════════════════════════════');
    debugPrint('[MyForegroundTaskHandler] ✓ onDestroy called');
    debugPrint('[MyForegroundTaskHandler]   Timestamp: $timestamp');
    debugPrint('[MyForegroundTaskHandler]   isTimeout: $isTimeout');
    debugPrint('╚═══════════════════════════════════════════════════════════');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[MyForegroundTaskHandler] onReceiveData: $data (type: ${data.runtimeType})');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[MyForegroundTaskHandler] onNotificationButtonPressed: id=$id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('[MyForegroundTaskHandler] onNotificationPressed - notification tapped');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[MyForegroundTaskHandler] onNotificationDismissed - notification dismissed');
  }
}

/// Service manager for controlling the foreground service.
///
/// Provides methods to start, stop, and monitor the foreground service.
class MonitoringService {
  static StreamSubscription<Object>? _taskDataSubscription;

  /// Initialize the foreground task with notification and task settings.
  ///
  /// Call this once at app startup (e.g., in main() before runApp()).
  static Future<void> init() async {
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[MonitoringService] Initializing foreground task...');

    // Initialize communication port for isolate communication
    FlutterForegroundTask.initCommunicationPort();
    debugPrint('[MonitoringService] ✓ Communication port initialized');

    // Initialize the foreground task with all options
    // Using minimal required parameters for AndroidNotificationOptions
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitoring_service_channel',
        channelName: 'Monitoring Service',
        channelDescription: 'Background monitoring service running every 1 second',
        onlyAlertOnce: true,
        showWhen: true,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // CRITICAL: Run every 1 second (1000 milliseconds)
        // This controls how often onRepeatEvent is called
        eventAction: ForegroundTaskEventAction.repeat(1000),
        // Allow wake lock to keep CPU running during sleep
        allowWakeLock: true,
        // Allow WiFi lock if needed
        allowWifiLock: true,
        // Auto run on boot (optional - set to true if needed)
        autoRunOnBoot: false,
        // Auto run when package is replaced (updated)
        autoRunOnMyPackageReplaced: true,
      ),
    );

    debugPrint('[MonitoringService] ✓ Foreground task initialized');
    debugPrint('[MonitoringService]   eventAction: repeat(1000ms)');
    debugPrint('[MonitoringService]   allowWakeLock: true');
    debugPrint('═══════════════════════════════════════════════════════════');
  }

  /// Check if the foreground service is running.
  static Future<bool> isRunning() async {
    final isRunning = FlutterForegroundTask.isRunningService;
    debugPrint('[MonitoringService] isRunningService: $isRunning');
    return isRunning;
  }

  /// Start the foreground service.
  ///
  /// This will:
  /// 1. Request notification permission (Android 13+)
  /// 2. Request battery optimization exemption
  /// 3. Start the foreground service with the callback
  static Future<void> startService() async {
    debugPrint('▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓');
    debugPrint('[MonitoringService] Starting foreground service...');

    // Check if already running
    final alreadyRunning = await isRunning();
    if (alreadyRunning) {
      debugPrint('[MonitoringService] ⚠ Service already running, skipping start');
      debugPrint('▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓');
      return;
    }

    // Request notification permission (Android 13+)
    debugPrint('[MonitoringService] Requesting notification permission...');
    final permission = await FlutterForegroundTask.requestNotificationPermission();
    debugPrint('[MonitoringService] Permission result: $permission');

    if (permission != NotificationPermission.granted) {
      debugPrint('[MonitoringService] ✗ Permission NOT granted: $permission');
      throw Exception('Notification permission not granted: $permission');
    }

    debugPrint('[MonitoringService] ✓ Notification permission granted');

    // Request battery optimization exemption for better reliability
    debugPrint('[MonitoringService] Requesting battery optimization exemption...');
    final batteryOptimized = await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    debugPrint('[MonitoringService] Battery optimization ignored: $batteryOptimized');

    // Start the service
    debugPrint('[MonitoringService] Calling FlutterForegroundTask.startService()...');
    debugPrint('[MonitoringService]   serviceId: 256');
    debugPrint('[MonitoringService]   callback: startCallback');

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Monitoring Service',
      notificationText: 'Running in background - tap to open app',
      // Use default app icon (must exist in Android resources)
      // If null, uses the default launcher icon
      notificationIcon: null,
      // The callback that will be executed in the isolate
      // This MUST be a top-level or static function
      callback: startCallback,
    );

    debugPrint('[MonitoringService] ✓ startService completed successfully');
    debugPrint('[MonitoringService] ✓ Service should now be running');
    debugPrint('[MonitoringService] ✓ onRepeatEvent will be called every 1 second');
    debugPrint('▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓');
  }

  /// Stop the foreground service.
  static Future<void> stopService() async {
    debugPrint('[MonitoringService] Stopping service...');

    if (await isRunning()) {
      await FlutterForegroundTask.stopService();
      debugPrint('[MonitoringService] ✓ Service stopped successfully');
    } else {
      debugPrint('[MonitoringService] ⚠ Service was not running');
    }
  }

  /// Update the notification while service is running.
  static Future<void> updateNotification({
    String? title,
    String? text,
  }) async {
    debugPrint('[MonitoringService] Updating notification: "$title" - "$text"');

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );

    debugPrint('[MonitoringService] ✓ Notification updated');
  }

  /// Send data from Flutter UI to the foreground task.
  static Future<void> sendDataToTask(dynamic data) async {
    debugPrint('[MonitoringService] sendDataToTask: $data (type: ${data.runtimeType})');
    FlutterForegroundTask.sendDataToTask(data);
  }

  /// Listen to data from the foreground task.
  ///
  /// The callback will be called every time the task sends data via sendDataToMain.
  /// Make sure to call this BEFORE starting the service.
  static void addDataCallback(Function(Object) callback) {
    debugPrint('[MonitoringService] Adding data callback');
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Remove data callback.
  static void removeDataCallback(Function(Object) callback) {
    debugPrint('[MonitoringService] Removing data callback');
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }

  /// Dispose resources.
  static void dispose() {
    _taskDataSubscription?.cancel();
    _taskDataSubscription = null;
  }
}
