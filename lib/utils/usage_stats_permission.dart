import 'package:usage_stats/usage_stats.dart';

/// Helper class to manage PACKAGE_USAGE_STATS permission on Android.
class UsageStatsPermission {
  /// Checks if the usage stats permission has been granted.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  /// On non-Android platforms, returns `false` as this permission is Android-specific.
  static Future<bool> checkPermission() async {
    try {
      final result = await UsageStats.checkUsagePermission();
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Requests the usage stats permission from the user by opening
  /// the Usage Access settings page.
  ///
  /// Note: This permission cannot be requested directly like runtime permissions.
  /// This method opens the settings page where the user must manually enable it.
  static Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  /// Redirects the user to the app's settings page where they can manually
  /// grant the Usage Access permission.
  ///
  /// Returns `true` if the settings page was opened successfully.
  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }

  /// Full flow to get usage stats permission.
  ///
  /// 1. Checks if permission is already granted.
  /// 2. If not, opens the Usage Access settings page.
  /// 3. User must manually enable permission in settings.
  ///
  /// Returns `true` if permission was already granted.
  /// Returns `false` if permission needs to be granted (settings opened).
  static Future<bool> getPermissionWithFallback() async {
    // Step 1: Check if already granted
    if (await checkPermission()) {
      return true;
    }

    // Step 2: Open Usage Access settings
    await requestPermission();

    return false;
  }
}
