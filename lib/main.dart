import 'package:flutter/material.dart';
import 'service/monitoring_service.dart';

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
      title: 'Foreground Service Demo',
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
  bool _isRunning = false;
  int _taskCount = 0;
  String _lastExecuted = 'Not running';
  String _lastDataType = '-';
  String _lastTimestamp = '-';
  Function(Object)? _dataCallback;

  @override
  void initState() {
    super.initState();
    debugPrint('[ForegroundServicePage] initState called');
    _checkServiceStatus();
    _setupTaskDataListener();
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
      debugPrint('[ForegroundServicePage] ✓ Data callback removed');
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

      // Parse the data
      String dataType = 'unknown';
      String timestamp = '-';

      if (data is Map) {
        dataType = data['type']?.toString() ?? 'unknown';
        timestamp = data['iso8601']?.toString() ?? '-';
        debugPrint('[ForegroundServicePage]   Data type: $dataType');
        debugPrint('[ForegroundServicePage]   Timestamp: $timestamp');
      } else if (data is int || data is num) {
        dataType = 'legacy_timestamp';
        timestamp = DateTime.fromMillisecondsSinceEpoch(
          (data as num).toInt(),
        ).toIso8601String();
      }

      // Use WidgetsBinding to ensure setState is called in the next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _taskCount++;
            _lastExecuted = DateTime.now().toString().substring(11, 19);
            _lastDataType = dataType;
            _lastTimestamp = timestamp;
          });

          debugPrint('[ForegroundServicePage] ✓ State updated');
          debugPrint('[ForegroundServicePage]   Task count: $_taskCount');
          debugPrint('[ForegroundServicePage]   Last executed: $_lastExecuted');
        }
      });

      debugPrint('└───────────────────────────────────────────────────────────');
    };

    // IMPORTANT: Register callback BEFORE starting the service
    MonitoringService.addDataCallback(_dataCallback!);
    debugPrint('[ForegroundServicePage] ✓ Task data callback registered');
  }

  Future<void> _startService() async {
    debugPrint('[ForegroundServicePage] Start service button PRESSED');

    try {
      debugPrint('[ForegroundServicePage] Calling MonitoringService.startService()...');
      await MonitoringService.startService();
      debugPrint('[ForegroundServicePage] ✓ Service start completed');

      await _checkServiceStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Foreground Service Started - Check logs for onRepeatEvent'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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
            duration: const Duration(seconds: 4),
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
          _lastDataType = '-';
          _lastTimestamp = '-';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foreground Service Stopped'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Foreground Service Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkServiceStatus,
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status indicator
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Task execution info
            _buildTaskInfoCard(),
            const SizedBox(height: 16),

            // Debug log info
            _buildDebugInfoCard(),
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
              _isRunning ? 'SERVICE RUNNING' : 'SERVICE STOPPED',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _isRunning ? Colors.green : Colors.red,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRunning
                  ? 'onRepeatEvent called every 1 second'
                  : 'Tap "Start Service" to begin',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskInfoCard() {
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
                  'Task Execution Statistics',
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
                  label: 'Executions',
                  value: '$_taskCount',
                  color: Colors.blue,
                ),
                _buildStatItem(
                  icon: Icons.access_time,
                  label: 'Last Run',
                  value: _lastExecuted,
                  color: Colors.green,
                ),
              ],
            ),
            if (_taskCount > 0) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.data_object,
                    label: 'Data Type',
                    value: _lastDataType,
                    color: Colors.purple,
                  ),
                  _buildStatItem(
                    icon: Icons.calendar_today,
                    label: 'Timestamp',
                    value: _lastTimestamp.length > 12
                        ? _lastTimestamp.substring(11, 19)
                        : _lastTimestamp,
                    color: Colors.orange,
                  ),
                ],
              ),
            ],
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

  Widget _buildDebugInfoCard() {
    return Card(
      elevation: 2,
      color: Colors.amber.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report, color: Colors.amber[700]),
                const SizedBox(width: 8),
                Text(
                  'Debug Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[900],
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildDebugRow('Callback registered', _dataCallback != null),
            _buildDebugRow('Widget mounted', mounted),
            _buildDebugRow('Listener active', _dataCallback != null && mounted),
            const SizedBox(height: 8),
            Text(
              'Check Android Logcat for detailed logs:\n'
              '  - Filter: "flutter"\n'
              '  - Look for: [MyForegroundTaskHandler] onRepeatEvent',
              style: TextStyle(fontSize: 12, color: Colors.amber[900]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugRow(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: value ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          const Spacer(),
          Text(
            value ? '✓' : '✗',
            style: TextStyle(
              fontSize: 13,
              color: value ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          onPressed: _isRunning ? null : _startService,
          icon: const Icon(Icons.play_arrow),
          label: const Text('START SERVICE'),
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
                  'Service Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow('Interval', '1 second (1000ms)'),
            _buildInfoRow('Service Type', 'dataSync'),
            _buildInfoRow('Wake Lock', 'Enabled'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expected Log Output:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '[MyForegroundTaskHandler] ✓ onRepeatEvent EXECUTED',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.blue[900],
                    ),
                  ),
                  Text(
                    '[ForegroundServicePage] ✓ DATA RECEIVED FROM STREAM',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.blue[900],
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Text(
            ': $value',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
