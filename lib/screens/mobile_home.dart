import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';

import '../services/http_client_service.dart';

class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

enum ConnectionStateStatus {
  scanning,
  pinRequired,
  connecting,
  connectionSuccess,
  connected,
  failed,
}

enum ConnectedView { menu, receive }

class _MobileHomeState extends State<MobileHome> {
  String? serverUrl;
  ConnectionStateStatus status = ConnectionStateStatus.scanning;
  ConnectedView connectedView = ConnectedView.menu;

  bool showScanner = false;
  bool _pinVerifying = false;
  String _pinError = '';

  final TextEditingController _pinController = TextEditingController();

  // Always recreated fresh — never reuse after stop/dispose
  MobileScannerController _scannerController = MobileScannerController();

  String? _lastScannedCode;
  DateTime? _lastScanTime;
  static const _scanCooldown = Duration(milliseconds: 1500);
  static const _minValidUrlLength = 10;

  Timer? _pingTimer;
  Timer? _filePollTimer;
  Timer? _successTimer;

  List<String> _availableFiles = [];

  // ================= LIFECYCLE =================

  @override
  void dispose() {
    _pingTimer?.cancel();
    _filePollTimer?.cancel();
    _successTimer?.cancel();
    _pinController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniShare – Mobile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Download history',
            onPressed: _showHistory,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (status) {
      case ConnectionStateStatus.scanning:
        return _buildScanner();
      case ConnectionStateStatus.pinRequired:
        return _buildPinInput();
      case ConnectionStateStatus.connecting:
        return _buildConnecting();
      case ConnectionStateStatus.connectionSuccess:
        return _buildConnectionSuccess();
      case ConnectionStateStatus.connected:
        return _buildConnected();
      case ConnectionStateStatus.failed:
        return _buildFailed();
    }
  }

  // ================= SCAN =================

  Widget _buildScanner() {
    if (!showScanner) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner, size: 72),
            const SizedBox(height: 20),
            const Text(
              'Connect to Desktop',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _startFreshScanner,
              child: const Text('Start Scanning'),
            ),
          ],
        ),
      );
    }

    const scanSize = 250.0;
    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onScanDetect),
        LayoutBuilder(
          builder: (context, constraints) => CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScanOverlayPainter(scanSize: scanSize),
          ),
        ),
        Center(
          child: Container(
            width: scanSize,
            height: scanSize,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green, width: 4),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  /// Dispose old controller and create a brand-new one before showing scanner.
  /// MobileScannerController cannot be reliably restarted after stop — must recreate.
  void _startFreshScanner() {
    _scannerController.dispose();
    _scannerController = MobileScannerController();
    _lastScannedCode = null;
    _lastScanTime = null;
    setState(() => showScanner = true);
  }

  void _onScanDetect(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;
    if (code == null || code.length < _minValidUrlLength) return;
    if (!code.startsWith('http://') && !code.startsWith('https://')) return;

    final now = DateTime.now();
    if (code == _lastScannedCode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < _scanCooldown) {
      return;
    }
    _lastScannedCode = code;
    _lastScanTime = now;
    _onQrScanned(code);
  }

  void _onQrScanned(String url) {
    setState(() {
      serverUrl = url;
      status = ConnectionStateStatus.pinRequired;
      showScanner = false;
      _pinError = '';
      _pinController.clear();
    });
  }

  // ================= PIN INPUT =================

  Widget _buildPinInput() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Enter PIN',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit PIN shown on desktop',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                obscureText: true,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  errorText: _pinError.isEmpty ? null : _pinError,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verifyPin(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _pinVerifying ? null : _verifyPin,
              child: _pinVerifying
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                status = ConnectionStateStatus.scanning;
                serverUrl = null;
              }),
              child: const Text('Scan Again'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _pinError = 'Enter 6 digits');
      return;
    }
    setState(() {
      _pinVerifying = true;
      _pinError = '';
    });
    final token = await HttpClientService.verifyPin(serverUrl!, pin);
    if (!mounted) return;
    if (token != null) {
      HttpClientService.authToken = token;
      setState(() {
        status = ConnectionStateStatus.connecting;
        _pinVerifying = false;
      });
      _checkConnection();
    } else {
      setState(() {
        _pinVerifying = false;
        _pinError =
            HttpClientService.lastVerifyError ?? 'Invalid PIN. Try again.';
      });
    }
  }

  // ================= CONNECTING =================

  Widget _buildConnecting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting to desktop...'),
        ],
      ),
    );
  }

  // ================= CONNECTION SUCCESS =================

  Widget _buildConnectionSuccess() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: const Icon(
                Icons.check_circle,
                size: 100,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Connection successful!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ================= CONNECTED =================

  Widget _buildConnected() {
    return connectedView == ConnectedView.menu
        ? _buildConnectedMenu()
        : _buildReceiveView();
  }

  Widget _buildConnectedMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: _disconnect,
            child: const Text('Close Connection'),
          ),
          const SizedBox(height: 40),
          FilledButton(onPressed: _sendFile, child: const Text('Send')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () =>
                setState(() => connectedView = ConnectedView.receive),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
  }

  // ================= RECEIVE VIEW =================

  Widget _buildReceiveView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () => setState(() => connectedView = ConnectedView.menu),
            child: const Text('Back'),
          ),
        ),
        Expanded(
          child: _availableFiles.isEmpty
              ? const Center(child: Text('Waiting for desktop files...'))
              : ListView.builder(
                  itemCount: _availableFiles.length,
                  itemBuilder: (context, index) {
                    final fileName = _availableFiles[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(fileName),
                      trailing: IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () => _downloadFile(fileName),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _downloadFile(String fileName) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savePath = await HttpClientService.getDownloadPath(fileName);
      await HttpClientService.downloadFile(serverUrl!, fileName, savePath);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('$fileName saved'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to download $fileName'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ================= FAILED =================

  Widget _buildFailed() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 72),
          const SizedBox(height: 16),
          const Text('Connection Failed'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              HttpClientService.authToken = null;
              setState(() {
                status = ConnectionStateStatus.scanning;
                serverUrl = null;
              });
            },
            child: const Text('Scan Again'),
          ),
        ],
      ),
    );
  }

  // ================= NETWORK =================

  Future<void> _checkConnection() async {
    try {
      final ok = await HttpClientService.ping(
        serverUrl!,
      ).timeout(const Duration(seconds: 8));
      if (ok) {
        setState(() => status = ConnectionStateStatus.connectionSuccess);
        _startHeartbeat();
        _startFilePolling();
        _successTimer?.cancel();
        _successTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          setState(() => status = ConnectionStateStatus.connected);
        });
      } else {
        _failConnection();
      }
    } catch (_) {
      _failConnection();
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final ok = await HttpClientService.ping(serverUrl!);
        if (!ok) _failConnection();
      } catch (_) {
        _failConnection();
      }
    });
  }

  void _startFilePolling() {
    _filePollTimer?.cancel();
    _filePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final files = await HttpClientService.getFiles(serverUrl!);
        if (!mounted) return;
        setState(() => _availableFiles = files);
      } catch (_) {}
    });
  }

  void _failConnection() {
    // Guard: prevent repeated calls from the heartbeat timer
    if (status == ConnectionStateStatus.failed) return;
    _pingTimer?.cancel();
    _filePollTimer?.cancel();
    _successTimer?.cancel();
    HttpClientService.authToken = null;
    if (!mounted) return;
    setState(() {
      status = ConnectionStateStatus.failed;
      _availableFiles.clear();
    });
  }

  void _disconnect() {
    _pingTimer?.cancel();
    _filePollTimer?.cancel();
    _successTimer?.cancel();
    HttpClientService.authToken = null;
    _lastScannedCode = null;
    _lastScanTime = null;

    // Dispose the broken controller and create a fresh one.
    // MobileScannerController cannot be reliably restarted — must be recreated.
    _scannerController.dispose();
    _scannerController = MobileScannerController();

    setState(() {
      status = ConnectionStateStatus.scanning;
      showScanner = true; // jump straight to scanner view
      serverUrl = null;
      connectedView = ConnectedView.menu;
      _availableFiles.clear();
      _pinController.clear();
      _pinError = '';
    });
  }

  // ================= SEND FILE =================

  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.first.path == null) return;

    final file = File(result.files.first.path!);
    final fileSize = await file.length();
    final fileName = result.files.first.name;

    // Pause heartbeat so the upload doesn't trigger a false disconnect
    _pingTimer?.cancel();

    if (!mounted) return;

    // Show animated bottom sheet during upload
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TransferSheet(fileName: fileName, fileSize: fileSize),
    );

    bool success = false;
    String? errorMsg;

    try {
      await HttpClientService.uploadFile(serverUrl!, file);
      success = true;
    } catch (_) {
      errorMsg = fileSize > 50 * 1024 * 1024
          ? 'Large file failed — check Wi-Fi'
          : 'Failed to send file';
    } finally {
      if (mounted) Navigator.of(context).pop(); // close bottom sheet
      // Always restart heartbeat after upload
      if (status == ConnectionStateStatus.connected) _startHeartbeat();
    }

    if (!mounted) return;

    _showTransferBanner(
      message: success
          ? '$fileName sent successfully'
          : (errorMsg ?? 'Transfer failed'),
      icon: success ? Icons.check_circle_rounded : Icons.error_rounded,
      color: success ? Colors.green : Colors.red,
    );
  }

  void _showTransferBanner({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= HISTORY =================

  Future<void> _showHistory() async {
    final files = await HttpClientService.getLocalHistory();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Downloaded Files'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: files.isEmpty
              ? const Center(child: Text('No downloads yet'))
              : ListView(
                  children: files
                      .map(
                        (f) => ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(f),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ================= SCAN OVERLAY =================

class _ScanOverlayPainter extends CustomPainter {
  final double scanSize;
  const _ScanOverlayPainter({required this.scanSize});

  @override
  void paint(Canvas canvas, Size size) {
    const dimColor = Color(0xCC000000);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final left = cx - scanSize / 2;
    final top = cy - scanSize / 2;
    final right = left + scanSize;
    final bottom = top + scanSize;
    final paint = Paint()..color = dimColor;

    if (top > 0) canvas.drawRect(Rect.fromLTWH(0, 0, size.width, top), paint);
    if (bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(0, bottom, size.width, size.height - bottom),
        paint,
      );
    }
    if (left > 0) canvas.drawRect(Rect.fromLTWH(0, top, left, scanSize), paint);
    if (right < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(right, top, size.width - right, scanSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================= TRANSFER SHEET =================

class _TransferSheet extends StatefulWidget {
  final String fileName;
  final int fileSize;
  const _TransferSheet({required this.fileName, required this.fileSize});

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Icon(
              Icons.upload_rounded,
              size: 48,
              color: Color.lerp(
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primaryContainer,
                _pulse.value,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Sending file…',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            widget.fileName,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _formatSize(widget.fileSize),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Please keep the app open',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
