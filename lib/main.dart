import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'service/monitoring_service.dart';
import 'utils/usage_stats_permission.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('╔═══════════════════════════════════════════════════════════');
  debugPrint('[main] Application starting...');

  // Initialize foreground service
  await MonitoringService.init();
  debugPrint('[main] ✓ Foreground service initialized');

  runApp(const MyApp());
  debugPrint('[main] ✓ MyApp started');
  debugPrint('╚═══════════════════════════════════════════════════════════');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sela - Zombie Scrolling Prevention',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ForegroundServicePage(),
    );
  }
}

class ForegroundServicePage extends StatefulWidget {
  const ForegroundServicePage({super.key});

  @override
  State<ForegroundServicePage> createState() => _ForegroundServicePageState();
}

class _ForegroundServicePageState extends State<ForegroundServicePage> {
  // Service status
  bool _isRunning = false;
  
  // Task execution counter
  int _taskCount = 0;
  String _lastExecuted = 'Not running';
  
  // App usage tracking
  String _activePackage = '-';
  int _appDuration = 0;
  bool _isTargetApp = false;
  
  // Permission status
  bool _hasUsageStatsPermission = false;
  
  // Callback reference
  Function(Object)? _dataCallback;

  @override
  void initState() {
    super.initState();
    debugPrint('[ForegroundServicePage] initState called');
    
    // Setup callback listener FIRST (before any service check)
    _setupTaskDataListener();
    
    // Check permission and service status
    _checkPermission();
    _checkServiceStatusAndReattach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('[ForegroundServicePage] didChangeDependencies called');
  }

  @override
  void didUpdateWidget(ForegroundServicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[ForegroundServicePage] didUpdateWidget called');
  }

  @override
  void deactivate() {
    debugPrint('[ForegroundServicePage] deactivate called');
    super.deactivate();
  }

  @override
  void dispose() {
    debugPrint('[ForegroundServicePage] dispose called');
    // Remove callback when widget is disposed
    if (_dataCallback != null) {
      MonitoringService.removeDataCallback(_dataCallback!);
    }
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    debugPrint('[ForegroundServicePage] Checking service status...');
    final isRunning = await MonitoringService.isRunning();
    debugPrint('[ForegroundServicePage] Service status: $isRunning');
    if (mounted) {
      setState(() {
        _isRunning = isRunning;
      });
    }
  }

  /// Check service status and re-attach if already running.
  /// This prevents service restart when app is reopened after being swiped away.
  Future<void> _checkServiceStatusAndReattach() async {
    debugPrint('[ForegroundServicePage] Checking service status for re-attachment...');
    
    // Check if service is already running
    final isRunning = await FlutterForegroundTask.isRunningService;
    debugPrint('[ForegroundServicePage] Service running: $isRunning');
    
    if (mounted) {
      setState(() {
        _isRunning = isRunning;
      });
      
      if (isRunning) {
        // Service is already running, request current state from service
        debugPrint('[ForegroundServicePage] ✓ Service re-attached, requesting current state...');
        
        // Request current state from the foreground service
        await MonitoringService.sendDataToTask({'type': 'request_state'});
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Monitoring service re-connected'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _checkPermission() async {
    debugPrint('[ForegroundServicePage] Checking usage stats permission...');
    final hasPermission = await UsageStatsPermission.checkPermission();
    debugPrint('[ForegroundServicePage] Permission status: $hasPermission');
    if (mounted) {
      setState(() {
        _hasUsageStatsPermission = hasPermission;
      });
    }
  }

  void _setupTaskDataListener() {
    debugPrint('[ForegroundServicePage] Setting up task data listener...');

    _dataCallback = (Object data) {
      debugPrint('┌───────────────────────────────────────────────────────────');
      debugPrint('[ForegroundServicePage] ✓ DATA CALLBACK RECEIVED');
      debugPrint('[ForegroundServicePage]   Data: $data');
      debugPrint('[ForegroundServicePage]   Type: ${data.runtimeType}');

      if (!mounted) {
        debugPrint('[ForegroundServicePage] ⚠ Widget not mounted, skipping UI update');
        debugPrint('└───────────────────────────────────────────────────────────');
        return;
      }

      // Parse the data based on type
      if (data is Map) {
        final dataType = data['type']?.toString() ?? 'unknown';
        debugPrint('[ForegroundServicePage]   Data type: $dataType');

        if (dataType == 'app_usage') {
          _handleAppUsageData(data);
        } else if (dataType == 'service_started') {
          debugPrint('[ForegroundServicePage]   Service started confirmation received');
        } else if (dataType == 'error') {
          final message = data['message']?.toString() ?? 'Unknown error';
          debugPrint('[ForegroundServicePage]   ✗ Error: $message');
        }
      }

      debugPrint('└───────────────────────────────────────────────────────────');
    };

    // IMPORTANT: Register callback BEFORE starting the service
    MonitoringService.addDataCallback(_dataCallback!);
    debugPrint('[ForegroundServicePage] ✓ Task data callback registered');
  }

  void _handleAppUsageData(Map data) {
    final packageName = data['active_package']?.toString() ?? 'unknown';
    // Support both 'duration' (legacy) and 'duration_seconds' (new)
    final duration = (data['duration_seconds'] as int? ?? data['duration'] as int?) ?? 0;
    final isTarget = data['is_target_app'] as bool? ?? false;
    final isReAttached = data['re_attached'] as bool? ?? false;

    debugPrint('[ForegroundServicePage]   App Usage Update:');
    debugPrint('[ForegroundServicePage]     Package: $packageName');
    debugPrint('[ForegroundServicePage]     Duration: ${duration}s');
    debugPrint('[ForegroundServicePage]     Is Target: $isTarget');
    if (isReAttached) {
      debugPrint('[ForegroundServicePage]     ✓ Re-attached from service');
    }

    // Directly call setState to trigger immediate UI refresh
    if (mounted) {
      setState(() {
        _activePackage = packageName;
        _appDuration = duration;
        _isTargetApp = isTarget;
        if (!isReAttached) {
          _taskCount++;
        }
        _lastExecuted = DateTime.now().toString().substring(11, 19);
      });
      debugPrint('[ForegroundServicePage]   ✓ State updated');
    }
  }

  Future<void> _requestPermission() async {
    debugPrint('[ForegroundServicePage] Requesting usage stats permission...');
    
    // Open usage access settings
    await UsageStatsPermission.requestPermission();
    
    // Wait for user to grant permission (poll for status)
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermission();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasUsageStatsPermission
                ? '✓ Permission granted!'
                : 'Please enable "Usage Access" permission in Settings',
          ),
          backgroundColor: _hasUsageStatsPermission ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _startService() async {
    debugPrint('[ForegroundServicePage] Start service button PRESSED');

    // Check permission first
    if (!_hasUsageStatsPermission) {
      debugPrint('[ForegroundServicePage] ⚠ No usage stats permission, showing dialog');
      _showPermissionDialog();
      return;
    }

    try {
      debugPrint('[ForegroundServicePage] Calling MonitoringService.startService()...');
      await MonitoringService.startService();
      debugPrint('[ForegroundServicePage] ✓ Service start completed');

      await _checkServiceStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ App Usage Monitor Started'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[ForegroundServicePage] ✗ ERROR starting service: $e');
      debugPrint('[ForegroundServicePage]   Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopService() async {
    debugPrint('[ForegroundServicePage] Stop service button PRESSED');

    try {
      debugPrint('[ForegroundServicePage] Calling MonitoringService.stopService()...');
      await MonitoringService.stopService();
      debugPrint('[ForegroundServicePage] ✓ Service stop completed');

      await _checkServiceStatus();

      if (mounted) {
        setState(() {
          _taskCount = 0;
          _lastExecuted = 'Not running';
          _activePackage = '-';
          _appDuration = 0;
          _isTargetApp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App Usage Monitor Stopped'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[ForegroundServicePage] ✗ ERROR stopping service: $e');
      debugPrint('[ForegroundServicePage]   Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.security, color: Colors.amber, size: 48),
        title: const Text('Permission Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To track app usage, this app needs "Usage Access" permission.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to grant permission:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber[900],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Tap "Grant Permission" below\n'
                    '2. Find "Sela Application" in the list\n'
                    '3. Toggle "Allow usage access" ON',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber[900],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _requestPermission();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Grant Permission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Sela - Usage Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _checkServiceStatus();
              _checkPermission();
            },
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Service status
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Active app tracking
            _buildActiveAppCard(),
            const SizedBox(height: 16),

            // Permission status
            _buildPermissionCard(),
            const SizedBox(height: 16),

            // Statistics
            _buildStatsCard(),
            const SizedBox(height: 24),

            // Control buttons
            _buildControlButtons(),
            const SizedBox(height: 16),

            // Info card
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRunning
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                border: Border.all(
                  color: _isRunning ? Colors.green : Colors.red,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isRunning ? Colors.green : Colors.red).withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isRunning ? Icons.play_circle : Icons.stop_circle,
                size: 80,
                color: _isRunning ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isRunning ? 'MONITORING ACTIVE' : 'MONITORING STOPPED',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _isRunning ? Colors.green : Colors.red,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRunning
                  ? 'Tracking app usage every 1 second'
                  : 'Tap "Start Monitoring" to begin',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAppCard() {
    final appDisplayName = _getAppDisplayName(_activePackage);
    final appIcon = _getAppIcon(_activePackage);
    
    return Card(
      elevation: 2,
      color: _isTargetApp 
          ? Colors.red.withOpacity(0.05) 
          : Colors.blue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isTargetApp ? Icons.warning : Icons.apps,
                  color: _isTargetApp ? Colors.red[700] : Colors.blue[700],
                ),
                const SizedBox(width: 8),
                Text(
                  _isTargetApp ? 'Target App Detected!' : 'Currently Active App',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isTargetApp ? Colors.red[700] : Colors.blue[700],
                      ),
                ),
                if (_isTargetApp) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ZOMBIE SCROLL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                // App icon placeholder
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _isTargetApp ? Colors.red[100] : Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      appIcon,
                      size: 32,
                      color: _isTargetApp ? Colors.red[700] : Colors.blue[700],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appDisplayName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _activePackage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Duration counter
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isTargetApp 
                    ? Colors.red.withOpacity(0.1) 
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isTargetApp ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: _isTargetApp ? Colors.red[700] : Colors.green[700],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Duration: ${_appDuration}s',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isTargetApp ? Colors.red[700] : Colors.green[700],
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard() {
    return Card(
      elevation: 2,
      color: _hasUsageStatsPermission 
          ? Colors.green.withOpacity(0.05) 
          : Colors.amber.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _hasUsageStatsPermission ? Icons.verified_user : Icons.security,
              color: _hasUsageStatsPermission ? Colors.green[700] : Colors.amber[700],
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usage Access Permission',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hasUsageStatsPermission
                        ? 'Permission granted ✓'
                        : 'Permission required - tap to grant',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _hasUsageStatsPermission 
                              ? Colors.green[700] 
                              : Colors.amber[700],
                        ),
                  ),
                ],
              ),
            ),
            if (!_hasUsageStatsPermission)
              ElevatedButton(
                onPressed: _requestPermission,
                child: const Text('Grant'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Session Statistics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  icon: Icons.timer,
                  label: 'Updates',
                  value: '$_taskCount',
                  color: Colors.blue,
                ),
                _buildStatItem(
                  icon: Icons.access_time,
                  label: 'Last Update',
                  value: _lastExecuted,
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _isRunning ? null : _startService,
              icon: const Icon(Icons.play_arrow),
              label: const Text('START MONITORING'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                disabledBackgroundColor: Colors.grey,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _isRunning ? _stopService : null,
              icon: const Icon(Icons.stop),
              label: const Text('STOP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                disabledBackgroundColor: Colors.grey,
              ),
            ),
          ],
        ),
        if (!_hasUsageStatsPermission) ...[
          const SizedBox(height: 12),
          Text(
            '⚠ Grant "Usage Access" permission to start monitoring',
            style: TextStyle(color: Colors.amber[900], fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Monitored Apps',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildAppChip('Instagram', Colors.purple),
                _buildAppChip('TikTok', Colors.black),
                _buildAppChip('YouTube', Colors.red),
                _buildAppChip('Facebook', Colors.blue),
                _buildAppChip('Twitter/X', Colors.blue[900]!),
                _buildAppChip('Snapchat', Colors.yellow[700]!),
                _buildAppChip('Reddit', Colors.orange),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'App usage is tracked every 1 second. Duration resets when you switch to a different app.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppChip(String label, Color color) {
    return Chip(
      avatar: Icon(Icons.close, size: 16, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
    );
  }

  String _getAppDisplayName(String packageName) {
    switch (packageName) {
      case 'com.instagram.android':
        return 'Instagram';
      case 'com.zhiliaoapp.musically':
        return 'TikTok';
      case 'com.google.android.youtube':
        return 'YouTube';
      case 'com.facebook.katana':
        return 'Facebook';
      case 'com.twitter.android':
        return 'Twitter/X';
      case 'com.snapchat.android':
        return 'Snapchat';
      case 'com.reddit.frontpage':
        return 'Reddit';
      case 'com.example.sela_application':
        return 'Sela (This App)';
      case 'unknown':
        return 'Unknown App';
      default:
        // Check if it's the Sela app (fallback)
        if (packageName.contains('sela')) {
          return 'Sela (This App)';
        }
        return packageName;
    }
  }

  IconData _getAppIcon(String packageName) {
    switch (packageName) {
      case 'com.instagram.android':
        return Icons.camera_alt;
      case 'com.zhiliaoapp.musically':
        return Icons.music_note;
      case 'com.google.android.youtube':
        return Icons.play_circle;
      case 'com.facebook.katana':
        return Icons.people;
      case 'com.twitter.android':
        return Icons.alternate_email;
      case 'com.snapchat.android':
        return Icons.face;  // Snapchat - using face icon as placeholder
      case 'com.reddit.frontpage':
        return Icons.forum;
      case 'com.example.sela_application':
        return Icons.shield;
      default:
        // Check if it's the Sela app (fallback)
        if (packageName.contains('sela')) {
          return Icons.shield;
        }
        return Icons.apps;
    }
  }
}
