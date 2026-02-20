import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter/foundation.dart';

/// List of target apps to monitor (zombie scrolling apps).
/// These apps will be tracked for usage duration.
const List<String> kTargetApps = [
  'com.instagram.android',        // Instagram
  'com.zhiliaoapp.musically',     // TikTok
  'com.google.android.youtube',   // YouTube
  'com.facebook.katana',          // Facebook
  'com.twitter.android',          // Twitter/X
  'com.snapchat.android',         // Snapchat
  'com.reddit.frontpage',         // Reddit
];

/// Package name for this app (Sela Application)
const String kSelaPackageName = 'com.example.sela_application';

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
  debugPrint('[MonitoringService] ✓ Target apps: ${kTargetApps.length} apps configured');
  debugPrint('[MonitoringService] ✓ Sela package: $kSelaPackageName');
}

/// Foreground task handler that executes every 1 second.
///
/// This class handles all foreground task lifecycle events and tracks
/// app usage statistics using UsageStats API.
class MyForegroundTaskHandler extends TaskHandler {
  /// Currently active app package name
  String _currentApp = '';

  /// Duration in seconds that the current app has been in foreground
  int _currentAppDuration = 0;

  /// Last tracked app package name (for detecting app switches)
  String _lastApp = '';

  /// Last notification text to avoid redundant updates
  String _lastNotificationText = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('╔═══════════════════════════════════════════════════════════');
    debugPrint('[MyForegroundTaskHandler] ✓ onStart called');
    debugPrint('[MyForegroundTaskHandler]   Timestamp: $timestamp');
    debugPrint('[MyForegroundTaskHandler]   TaskStarter: ${starter.name}');
    debugPrint('[MyForegroundTaskHandler]   Target apps configured: ${kTargetApps.length}');

    try {
      // Send initial data to UI to confirm service started
      final initData = <String, dynamic>{
        'type': 'service_started',
        'timestamp': timestamp.millisecondsSinceEpoch,
        'iso8601': timestamp.toIso8601String(),
        'starter': starter.name,
        'target_apps_count': kTargetApps.length,
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

    // Query usage stats asynchronously
    _queryAndTrackApp(timestamp);

    debugPrint('└───────────────────────────────────────────────────────────');
  }

  /// Query usage stats and track app usage asynchronously.
  ///
  /// This method handles the async UsageStats query and sends data to UI.
  Future<void> _queryAndTrackApp(DateTime timestamp) async {
    try {
      debugPrint('[MyForegroundTaskHandler]   Querying UsageStats...');

      // Query for the last 1 second
      final now = DateTime.now();
      final oneSecondAgo = now.subtract(const Duration(seconds: 1));

      // Query usage stats - this is async
      final usageStats = await UsageStats.queryUsageStats(oneSecondAgo, now);

      if (usageStats.isEmpty) {
        debugPrint('[MyForegroundTaskHandler]   ⚠ No usage stats found (user likely in Sela app)');

        // When no usage stats found, assume user is in Sela app itself
        // This happens because UsageStats doesn't track the current app while in foreground
        if (_lastApp == kSelaPackageName) {
          // Still in Sela app, increment duration
          _currentAppDuration++;
          debugPrint('[MyForegroundTaskHandler]   User in Sela app, duration: ${_currentAppDuration}s');
        } else {
          // Just switched to Sela app
          if (_lastApp.isNotEmpty) {
            debugPrint('[MyForegroundTaskHandler]   App switched from $_lastApp to Sela');
          }
          _lastApp = kSelaPackageName;
          _currentAppDuration = 1;
        }

        // Send Sela app data
        FlutterForegroundTask.sendDataToMain(<String, dynamic>{
          'type': 'app_usage',
          'active_package': kSelaPackageName,
          'app_name': 'Sela (This App)',
          'duration_seconds': _currentAppDuration,
          'duration_formatted': _formatDuration(_currentAppDuration),
          'is_target_app': false,
          'timestamp': timestamp.toIso8601String(),
          'milliseconds': timestamp.millisecondsSinceEpoch,
        });
        return;
      }

      debugPrint('[MyForegroundTaskHandler]   Found ${usageStats.length} apps in usage stats');

      // Find the app with the most recent lastTimeUsed
      String? mostRecentPackage;
      int mostRecentTime = 0;

      for (final stat in usageStats) {
        final packageName = stat.packageName;
        final lastTimeUsed = stat.lastTimeUsed;

        if (packageName != null && lastTimeUsed != null) {
          // Parse lastTimeUsed (it's a string timestamp in milliseconds)
          final lastTimeMs = int.tryParse(lastTimeUsed) ?? 0;

          if (lastTimeMs > mostRecentTime) {
            mostRecentTime = lastTimeMs;
            mostRecentPackage = packageName;
          }
        }
      }

      if (mostRecentPackage != null) {
        debugPrint('[MyForegroundTaskHandler]   Most recent app: $mostRecentPackage (${mostRecentTime}ms)');

        // Check if it's the Sela app itself
        String displayPackage = mostRecentPackage;
        String appName = 'Unknown App';

        if (mostRecentPackage == kSelaPackageName ||
            mostRecentPackage.contains('sela_application')) {
          displayPackage = kSelaPackageName;
          appName = 'Sela (This App)';
          debugPrint('[MyForegroundTaskHandler]   Detected: User is in Sela app');
        }

        final isTargetApp = kTargetApps.contains(mostRecentPackage);

        // Track duration
        if (mostRecentPackage == _lastApp) {
          // Same app, increment duration
          _currentAppDuration++;
          debugPrint('[MyForegroundTaskHandler]   Same app: $appName, duration: ${_currentAppDuration}s');
        } else {
          // App switched, reset duration
          if (_lastApp.isNotEmpty) {
            debugPrint('[MyForegroundTaskHandler]   App switched from $_lastApp to $appName');
          }
          _lastApp = mostRecentPackage;
          _currentApp = mostRecentPackage;
          _currentAppDuration = 1; // Start counting from 1
        }

        // Format duration as HH:mm:ss
        final formattedDuration = _formatDuration(_currentAppDuration);

        // Prepare data to send to UI
        final appUsageData = <String, dynamic>{
          'type': 'app_usage',
          'active_package': displayPackage,
          'app_name': appName,
          'duration_seconds': _currentAppDuration,
          'duration_formatted': formattedDuration,
          'is_target_app': isTargetApp,
          'timestamp': timestamp.toIso8601String(),
          'milliseconds': timestamp.millisecondsSinceEpoch,
        };

        FlutterForegroundTask.sendDataToMain(appUsageData);
        debugPrint('[MyForegroundTaskHandler] ✓ App usage data sent:');
        debugPrint('[MyForegroundTaskHandler]   Package: $appName ($displayPackage)');
        debugPrint('[MyForegroundTaskHandler]   Duration: $formattedDuration (${_currentAppDuration}s)');
        debugPrint('[MyForegroundTaskHandler]   Is Target: $isTargetApp');

        // Update notification with current app info
        _updateNotification(appName, formattedDuration, isTargetApp);
      } else {
        // No package detected - assume user is in Sela app
        debugPrint('[MyForegroundTaskHandler] ⚠ No package detected, assuming Sela app');

        if (_lastApp == kSelaPackageName) {
          _currentAppDuration++;
        } else {
          _lastApp = kSelaPackageName;
          _currentAppDuration = 1;
        }

        FlutterForegroundTask.sendDataToMain(<String, dynamic>{
          'type': 'app_usage',
          'active_package': kSelaPackageName,
          'app_name': 'Sela (This App)',
          'duration_seconds': _currentAppDuration,
          'duration_formatted': _formatDuration(_currentAppDuration),
          'is_target_app': false,
          'timestamp': timestamp.toIso8601String(),
          'milliseconds': timestamp.millisecondsSinceEpoch,
        });

        // Update notification for Sela app
        _updateNotification('Sela (This App)', _formatDuration(_currentAppDuration), false);
      }
    } catch (e, stackTrace) {
      debugPrint('[MyForegroundTaskHandler] ✗ Error in _queryAndTrackApp: $e');
      debugPrint('[MyForegroundTaskHandler]   Stack: $stackTrace');

      // Send error data to UI
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'type': 'error',
        'message': e.toString(),
        'timestamp': timestamp.toIso8601String(),
      });
    }
  }

  /// Update the foreground notification with current app info.
  void _updateNotification(String appName, String duration, bool isTargetApp) {
    // Create notification text with emoji indicators
    String notificationText;
    if (isTargetApp) {
      // Target app detected (zombie scroll apps)
      notificationText = '⚠️ ZOMBIE SCROLL: $appName - $duration';
    } else if (appName == 'Sela (This App)') {
      // User is in Sela app
      notificationText = '🛡️ Sela Active - Monitoring...';
    } else {
      // Other apps
      notificationText = '📱 $appName - $duration';
    }

    // Only update if text changed (to avoid excessive updates)
    if (notificationText != _lastNotificationText) {
      _lastNotificationText = notificationText;
      
      // Update notification using FlutterForegroundTask
      FlutterForegroundTask.updateService(
        notificationTitle: 'App Usage Monitor',
        notificationText: notificationText,
      );
      
      debugPrint('[MyForegroundTaskHandler]   📢 Notification updated: $notificationText');
    }
  }

  /// Format duration in seconds to HH:mm:ss format.
  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    // Always include hours if > 0, otherwise just mm:ss
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('╔═══════════════════════════════════════════════════════════');
    debugPrint('[MyForegroundTaskHandler] ✓ onDestroy called');
    debugPrint('[MyForegroundTaskHandler]   Timestamp: $timestamp');
    debugPrint('[MyForegroundTaskHandler]   isTimeout: $isTimeout');
    debugPrint('[MyForegroundTaskHandler]   Final tracked app: $_currentApp');
    debugPrint('[MyForegroundTaskHandler]   Final duration: ${_currentAppDuration}s');
    debugPrint('╚═══════════════════════════════════════════════════════════');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[MyForegroundTaskHandler] onReceiveData: $data (type: ${data.runtimeType})');
    
    // When UI requests current state (re-attachment), send the latest data
    if (data is Map && data['type'] == 'request_state') {
      debugPrint('[MyForegroundTaskHandler]   UI requesting state, sending current app data...');
      
      final appUsageData = <String, dynamic>{
        'type': 'app_usage',
        'active_package': _currentApp.isNotEmpty ? _currentApp : kSelaPackageName,
        'app_name': _currentApp.isNotEmpty ? _getAppName(_currentApp) : 'Sela (This App)',
        'duration_seconds': _currentAppDuration,
        'duration_formatted': _formatDuration(_currentAppDuration),
        'is_target_app': kTargetApps.contains(_currentApp),
        'timestamp': DateTime.now().toIso8601String(),
        're_attached': true,
      };
      
      FlutterForegroundTask.sendDataToMain(appUsageData);
      debugPrint('[MyForegroundTaskHandler]   ✓ State sent: ${appUsageData['active_package']}, duration: ${_currentAppDuration}s');
    }
  }

  /// Get app display name from package.
  String _getAppName(String packageName) {
    if (packageName == kSelaPackageName || packageName.contains('sela_application')) {
      return 'Sela (This App)';
    }
    switch (packageName) {
      case 'com.instagram.android': return 'Instagram';
      case 'com.zhiliaoapp.musically': return 'TikTok';
      case 'com.google.android.youtube': return 'YouTube';
      case 'com.facebook.katana': return 'Facebook';
      case 'com.twitter.android': return 'Twitter/X';
      case 'com.snapchat.android': return 'Snapchat';
      case 'com.reddit.frontpage': return 'Reddit';
      default: return packageName;
    }
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
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'monitoring_service_channel',
        channelName: 'Monitoring Service',
        channelDescription: 'Background monitoring service tracking app usage every 1 second',
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
    debugPrint('[MonitoringService]   Target apps: ${kTargetApps.length} configured');
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
      notificationTitle: '🛡️ App Usage Monitor',
      notificationText: '✓ Monitoring active - Tap to open',
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
}
