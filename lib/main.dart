import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_fonts/google_fonts.dart';

import 'service/monitoring_service.dart';
import 'utils/usage_stats_permission.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Make status bar transparent
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10b981)),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
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

class _ForegroundServicePageState extends State<ForegroundServicePage>
    with TickerProviderStateMixin {
  // Service status
  bool _isRunning = false;

  // Task execution counter
  int _taskCount = 0;

  // App usage tracking
  String _activePackage = '-';
  int _appDuration = 0;
  bool _isTargetApp = false;

  // Permission status
  bool _hasUsageStatsPermission = false;

  // Callback reference
  Function(Object)? _dataCallback;

  // Animation controllers
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    debugPrint('[ForegroundServicePage] initState called');

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Setup callback listener FIRST (before any service check)
    _setupTaskDataListener();

    // Check permission and service status
    _checkPermission();
    _checkServiceStatusAndReattach();
  }

  @override
  void dispose() {
    debugPrint('[ForegroundServicePage] dispose called');
    _rippleController.dispose();
    if (_dataCallback != null) {
      MonitoringService.removeDataCallback(_dataCallback!);
    }
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await MonitoringService.isRunning();
    if (mounted) {
      setState(() {
        _isRunning = isRunning;
        if (_isRunning) {
          _rippleController.repeat();
        } else {
          _rippleController.stop();
          _rippleController.reset();
        }
      });
    }
  }

  Future<void> _checkServiceStatusAndReattach() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (mounted) {
      setState(() {
        _isRunning = isRunning;
        if (_isRunning) {
          _rippleController.repeat();
        }
      });

      if (isRunning) {
        await MonitoringService.sendDataToTask({'type': 'request_state'});
      }
    }
  }

  Future<void> _checkPermission() async {
    final hasPermission = await UsageStatsPermission.checkPermission();
    if (mounted) {
      setState(() {
        _hasUsageStatsPermission = hasPermission;
      });
    }
  }

  void _setupTaskDataListener() {
    _dataCallback = (Object data) {
      if (!mounted) return;

      if (data is Map) {
        final dataType = data['type']?.toString() ?? 'unknown';

        if (dataType == 'app_usage') {
          _handleAppUsageData(data);
        }
      }
    };
    MonitoringService.addDataCallback(_dataCallback!);
  }

  void _handleAppUsageData(Map data) {
    final packageName = data['active_package']?.toString() ?? 'unknown';
    final duration =
        (data['duration_seconds'] as int? ?? data['duration'] as int?) ?? 0;
    final isTarget = data['is_target_app'] as bool? ?? false;
    final isReAttached = data['re_attached'] as bool? ?? false;

    if (mounted) {
      setState(() {
        _activePackage = packageName;
        _appDuration = duration;
        _isTargetApp = isTarget;
        if (!isReAttached) {
          _taskCount++;
        }
      });
    }
  }

  Future<void> _requestPermission() async {
    await UsageStatsPermission.requestPermission();
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermission();
  }

  Future<void> _toggleService() async {
    if (_isRunning) {
      await _stopService();
    } else {
      await _startService();
    }
  }

  Future<void> _startService() async {
    if (!_hasUsageStatsPermission) {
      _showPermissionDialog();
      return;
    }

    try {
      await MonitoringService.startService();
      await _checkServiceStatus();
    } catch (e) {
      debugPrint('[ForegroundServicePage] ✗ ERROR starting service: $e');
    }
  }

  Future<void> _stopService() async {
    try {
      await MonitoringService.stopService();
      await _checkServiceStatus();
      if (mounted) {
        setState(() {
          _taskCount = 0;
          _activePackage = '-';
          _appDuration = 0;
          _isTargetApp = false;
        });
      }
    } catch (e) {
      debugPrint('[ForegroundServicePage] ✗ ERROR stopping service: $e');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.security_rounded, color: Colors.amber, size: 48),
        title: Text(
          'Izin Diperlukan',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agar dapat mendeteksi zombie scroll, aplikasi membutuhkan izin "Usage Access".',
              style: GoogleFonts.inter(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Berikan Izin',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf8fafc),
      body: Stack(
        children: [
          // Background Mesh Gradient
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF10b981).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                color: const Color(0xFF6366f1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _buildHeader(),
                    if (!_hasUsageStatsPermission) ...[
                      const SizedBox(height: 16),
                      _buildPermissionWarning(),
                    ],
                    const SizedBox(height: 32),
                    _buildMainActionCard(),
                    const SizedBox(height: 32),
                    _buildStatsGlassCard(),
                    const SizedBox(height: 24),
                    _buildFocusCard(),
                    const SizedBox(height: 100), // Space for floating nav
                  ],
                ),
              ),
            ),
          ),

          // Floating Navigation
          _buildFloatingNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1e293b),
              height: 1.1,
            ),
            children: [
              const TextSpan(text: 'Sedang mengejar apa\n'),
              TextSpan(
                text: 'hari ini, Jefta?',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF10b981),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionWarning() {
    return InkWell(
      onTap: _requestPermission,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Akses penggunaan diperlukan untuk memonitor aplikasi.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActionCard() {
    return Center(
      child: GestureDetector(
        onTap: _toggleService,
        child: SizedBox(
          width: 240,
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple effect
              if (_isRunning)
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _rippleController,
                    builder: (context, child) {
                      // Delay effect
                      double value = _rippleController.value - (index * 0.3);
                      if (value < 0) value += 1.0;
                      return Transform.scale(
                        scale: 1.0 + (value * 0.6),
                        child: Opacity(
                          opacity: (1.0 - value).clamp(0.0, 0.5),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF10b981),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),

              // Button Surrounding Glow
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF34d399).withOpacity(0.4),
                      const Color(0xFF10b981).withOpacity(0.1),
                    ],
                  ),
                ),
              ),

              // Solid Button Core
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: _isRunning
                          ? const Color(0xFF10b981).withOpacity(0.3)
                          : Colors.black.withOpacity(0.05),
                      blurRadius: 30,
                      spreadRadius: -5,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 4,
                      blurStyle: BlurStyle.inner,
                    ),
                  ],
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFf1f5f9)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRunning ? Icons.eco_rounded : Icons.eco_outlined,
                      size: 48,
                      color: const Color(0xFF10b981),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRunning ? 'STOP' : 'START',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1e293b),
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'MONITORING',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748b),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGlassCard() {
    int minutes = _appDuration ~/ 60;
    int seconds = _appDuration % 60;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366f1).withOpacity(0.05),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aktifitas Saat Ini',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748b),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      minutes.toString().padLeft(2, '0'),
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1e293b),
                      ),
                    ),
                    Text(
                      'm',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94a3b8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      seconds.toString().padLeft(2, '0'),
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1e293b),
                      ),
                    ),
                    Text(
                      's',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94a3b8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isTargetApp
                        ? Colors.red.withOpacity(0.1)
                        : Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isTargetApp
                          ? Colors.red.withOpacity(0.3)
                          : const Color(0xFF10b981).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isTargetApp ? Icons.warning_rounded : Icons.apps_rounded,
                        size: 14,
                        color: _isTargetApp
                            ? Colors.red
                            : const Color(0xFF10b981),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _getAppDisplayName(_activePackage),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isTargetApp
                                ? Colors.red[700]
                                : const Color(0xFF10b981),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Custom Circular Progress for decorative stats
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 6,
                  color: const Color(0xFFe2e8f0),
                ),
                CircularProgressIndicator(
                  // Dummy progress based on time for visual effect
                  value: (_appDuration > 0) ? (_appDuration % 60) / 60 : 0.0,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  color: const Color(0xFF6366f1),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_taskCount}',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1e293b),
                      ),
                    ),
                    Text(
                      'CALLS',
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748b),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10b981).withOpacity(0.02),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366f1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.psychology_rounded,
                    color: Color(0xFF6366f1)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fokus Saat Ini',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1e293b),
                  ),
                ),
              ),
              const Icon(Icons.more_horiz_rounded,
                  color: Color(0xFF94a3b8)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFF10b981), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Belajar Full-stack (Flutter)',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1e293b),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Terus maju, satu per satu.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF64748b),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'AKSI KECIL HARI INI',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF94a3b8),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildChecklistItem('Setup Environment', true),
          _buildChecklistItem('Tonton Tutorial Ep. 1', false),
          _buildChecklistItem('Push commit pertama', false),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String title, bool isCompleted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isCompleted ? const Color(0xFF10b981) : Colors.transparent,
              border: Border.all(
                color: isCompleted
                    ? const Color(0xFF10b981)
                    : const Color(0xFFcbd5e1),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: isCompleted
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isCompleted
                  ? const Color(0xFF94a3b8)
                  : const Color(0xFF334155),
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNav() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNavItem(Icons.home_rounded, true),
              const SizedBox(width: 24),
              _buildNavItem(Icons.bar_chart_rounded, false),
              const SizedBox(width: 24),
              _buildNavItem(Icons.psychology_rounded, false),
              const SizedBox(width: 24),
              _buildNavItem(Icons.settings_rounded, false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF10b981).withOpacity(0.15)
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: isActive ? const Color(0xFF10b981) : const Color(0xFF94a3b8),
        size: 26,
      ),
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
      case '-':
        return 'Tidak ada aplikasi terbuka';
      case 'unknown':
        return 'Sistem / Tidak Diketahui';
      default:
        if (packageName.contains('sela')) {
          return 'Sela (This App)';
        }
        return packageName.split('.').last.toUpperCase();
    }
  }
}
