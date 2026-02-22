import 'dart:io';
import 'dart:async';

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();

  factory NetworkMonitor() {
    return _instance;
  }

  NetworkMonitor._internal();

  final StreamController<String?> _ipChangeController =
      StreamController<String?>.broadcast();

  Timer? _detectionTimer;
  String? _lastDetectedIp;

  void startMonitoring() {
    // Check every 2 seconds if IP changed
    _detectionTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final newIp = await _detectLocalIp();
      if (newIp != _lastDetectedIp) {
        _lastDetectedIp = newIp;
        _ipChangeController.add(newIp);
        print('🔄 Network changed! New IP: $newIp');
      }
    });
  }

  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      // Priority order for Windows
      final preferredPatterns = [
        RegExp(r'ethernet', caseSensitive: false),
        RegExp(r'wi-?fi|wlan', caseSensitive: false),
        RegExp(r'hotspot|mobile|adapter', caseSensitive: false),
      ];

      // First pass: Match preferred patterns
      for (final pattern in preferredPatterns) {
        for (final iface in interfaces) {
          if (pattern.hasMatch(iface.name)) {
            final ip = _getValidIpFromInterface(iface);
            if (ip != null) return ip;
          }
        }
      }

      // Second pass: Any valid IP
      for (final iface in interfaces) {
        final ip = _getValidIpFromInterface(iface);
        if (ip != null) return ip;
      }
    } catch (e) {
      print('Error detecting IP: $e');
    }
    return null;
  }

  String? _getValidIpFromInterface(NetworkInterface iface) {
    for (final addr in iface.addresses) {
      if (_isValidIp(addr.address)) {
        return addr.address;
      }
    }
    return null;
  }

  bool _isValidIp(String address) {
    // Exclude link-local addresses (169.254.x.x) - auto-assigned when no DHCP
    if (address.startsWith('169.254.')) {
      return false;
    }
    // Exclude loopback
    if (address.startsWith('127.')) {
      return false;
    }
    // Exclude IPv6
    if (address.startsWith('::')) {
      return false;
    }
    return true;
  }

  Stream<String?> get onIpChange => _ipChangeController.stream;

  void dispose() {
    _detectionTimer?.cancel();
    _ipChangeController.close();
  }
}
