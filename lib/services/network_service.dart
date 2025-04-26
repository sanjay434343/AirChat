import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:udp/udp.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/device.dart';
import '../models/profile.dart';

class NetworkService {
  static const int udpPort = 42420; // Changed from UDP_PORT
  static const Duration _discoveryTimeout = Duration(seconds: 15); // Reduced timeout
  static const Duration _retryInterval = Duration(seconds: 5);
  static const Duration _totalDiscoveryTimeout = Duration(seconds: 45);
  int _retryCount = 0;
  static const int maxRetries = 3;
  bool _useLegacyMode = false;
  UDP? _sender;
  UDP? _receiver;
  Timer? _broadcastTimer;
  Timer? _discoveryTimeoutTimer;
  bool _isListening = true;
  bool _discoveryCompleted = false;
  final StreamController<Device> _deviceController = StreamController<Device>.broadcast();
  Stream<Device> get deviceStream => _deviceController.stream;
  late Profile _profile;
  
  Future<String?> _getNetworkIP() async {
    try {
      // Try multiple methods to get IP
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      
      if (ip == null || ip.isEmpty) {
        final interfaces = await NetworkInterface.list(includeLinkLocal: true, type: InternetAddressType.IPv4);
        for (var interface in interfaces) {
          // Check for both WiFi and mobile hotspot interfaces
          if (interface.name.toLowerCase().contains('wlan') || 
              interface.name.toLowerCase().contains('ap') ||
              interface.name.toLowerCase().contains('wifi') ||
              interface.name.toLowerCase().contains('ethernet')) {
            for (var addr in interface.addresses) {
              if (_isLocalNetworkIP(addr.address)) {
                return addr.address;
              }
            }
          }
        }
      }
      return ip;
    } catch (e) {
      print('IP detection error: $e');
      return null;
    }
  }

  Future<void> startDiscovery(Profile profile) async {
    _profile = profile;
    String? ip = await _getNetworkIP();
    
    // Set overall timeout
    _discoveryTimeoutTimer = Timer(_totalDiscoveryTimeout, () {
      if (!_discoveryCompleted && !_deviceController.isClosed) {
        _discoveryCompleted = true;
        // Add empty device to signal completion
        _deviceController.add(Device(
          id: 'timeout',
          name: 'No devices found',
          ip: '0.0.0.0',
          port: udpPort,
          profile: profile,
        ));
      }
    });

    if (ip == null) {
      ip = await _tryCommonIPs() ?? '0.0.0.0';
    }

    try {
      await _initializeNetwork(ip);
    } catch (e) {
      print('Network initialization failed: $e');
      // Ensure we send completion signal even on failure
      if (!_discoveryCompleted && !_deviceController.isClosed) {
        _discoveryCompleted = true;
        _deviceController.add(Device(
          id: 'error',
          name: 'Network Error',
          ip: '0.0.0.0',
          port: udpPort,
          profile: profile,
        ));
      }
    }
  }

  Future<void> _initializeNetwork(String ip) async {
    int retryAttempts = 0;
    const maxRetries = 3;

    while (retryAttempts < maxRetries && !_discoveryCompleted) {
      try {
        _sender = await UDP.bind(Endpoint.any(port: Port(0)))
            .timeout(const Duration(seconds: 5));
            
        _receiver = await UDP.bind(Endpoint.any(port: Port(udpPort)))
            .timeout(const Duration(seconds: 5));

        _broadcastPresence(ip);
        _startListening();
        _setupAutoRetry(ip);
        break;
      } catch (e) {
        retryAttempts++;
        if (retryAttempts == maxRetries) {
          _useLegacyMode = true;
          _setupFallbackDiscovery(ip);
        }
        await Future.delayed(Duration(seconds: 2));
      }
    }
  }

  Future<UDP> _retryConnection(String ip) async {
    print('Retrying connection in legacy mode...');
    // Try multiple ports in sequence
    final ports = [udpPort + 1, udpPort + 2, 42422, 42423];
    for (var port in ports) {
      try {
        return await UDP.bind(Endpoint.any(port: Port(port)));
      } catch (e) {
        continue;
      }
    }
    throw Exception('Could not bind to any port');
  }

  void _setupAutoRetry(String ip) {
    Timer.periodic(_retryInterval, (timer) async {
      if (_retryCount >= maxRetries || _deviceController.isClosed) {
        timer.cancel();
        return;
      }
      
      if (!_deviceController.hasListener) {
        _retryCount++;
        _useLegacyMode = true;
        await _broadcastToSubnet(ip);
      }
    });
  }

  Future<void> _broadcastToSubnet(String ip) async {
    final subnet = ip.substring(0, ip.lastIndexOf('.'));
    final device = Device(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _profile.name,
      ip: ip,
      port: _useLegacyMode ? udpPort + 1 : udpPort,
      profile: _profile,
    );
    
    final data = utf8.encode(jsonEncode(device.toJson()));
    
    // Broadcast to common IP ranges
    for (var i = 1; i < 255; i++) {
      try {
        final targetIp = '$subnet.$i';
        if (targetIp != ip) {
          await _sender?.send(
            data,
            Endpoint.unicast(
              InternetAddress(targetIp),
              port: Port(_useLegacyMode ? udpPort + 1 : udpPort)
            )
          );
          await Future.delayed(Duration(milliseconds: 20));
        }
      } catch (e) {
        continue;
      }
    }
  }

  Future<String?> _tryCommonIPs() async {
    final commonSubnets = ['192.168.1.', '192.168.0.', '192.168.43.'];
    for (var subnet in commonSubnets) {
      try {
        final interfaces = await NetworkInterface.list();
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (addr.address.startsWith(subnet)) {
              return addr.address;
            }
          }
        }
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  void _setupRetryMechanism() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      // Changed hasValue check to check if stream has listeners
      if (_deviceController.hasListener && !_deviceController.isClosed) {
        _useLegacyMode = true;
        _broadcastPresence(_profile.ip);
      }
    });
  }

  void _setupFallbackDiscovery(String ip) {
    // Try alternative ports for older devices
    final alternatePorts = [42421, 42422, 42423];
    for (var port in alternatePorts) {
      try {
        UDP.bind(Endpoint.any(port: Port(port))).then((udp) {
          _receiver = udp;
          _startListening();
        });
      } catch (e) {
        print('Fallback port $port failed: $e');
        continue;
      }
    }
  }

  void _broadcastPresence(String ip) {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(
      Duration(seconds: _useLegacyMode ? 2 : 1),
      (timer) async {
        if (_sender == null || _discoveryCompleted) {
          timer.cancel();
          return;
        }
        
        try {
          final device = Device(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: _profile.name,
            ip: ip,
            port: _useLegacyMode ? udpPort + 1 : udpPort,
            profile: _profile,
          );
          
          final data = utf8.encode(jsonEncode(device.toJson()));
          
          // Check if socket is still valid
          if (_sender?.isClosed ?? true) {
            timer.cancel();
            return;
          }

          await _sender?.send(data, Endpoint.broadcast(
            port: Port(_useLegacyMode ? udpPort + 1 : udpPort)
          ));

          if (_useLegacyMode) {
            // ...existing legacy mode code...
          }
        } catch (e) {
          print('Error broadcasting presence: $e');
          // Stop timer if we keep getting errors
          if (e.toString().contains('Bad file descriptor')) {
            timer.cancel();
          }
        }
      }
    );
  }

  bool _isLocalNetworkIP(String ip) {
    return ip.startsWith('192.168.') || 
           ip.startsWith('172.') || 
           ip.startsWith('10.') ||
           ip.startsWith('169.254.'); // For direct WiFi connections
  }

  Future<void> _startListening() async {
    if (_receiver == null) return;
    print('Started listening on port $udpPort');
    
    try {
      await for (final datagram in _receiver!.asStream()) {
        if (!_isListening || _deviceController.isClosed) break;
        
        try {
          final data = utf8.decode(datagram?.data as List<int>);
          final device = Device.fromJson(jsonDecode(data));
          final currentIp = await NetworkInfo().getWifiIP() ?? 
                          (await _getNetworkIP() ?? '0.0.0.0');
          
          // Only add device if it's not self and is on local network
          if (device.ip != currentIp && 
              _isLocalNetworkIP(device.ip) &&
              device.profile.name != _profile.name) {
            print('Device connected: ${device.name} at ${device.ip}');
            _deviceController.add(device);
          }
        } catch (e) {
          print('Error processing received data: $e');
        }
      }
    } catch (e) {
      print('Error in listening loop: $e');
      rethrow;
    }
  }

  Future<void> connectViaQR(Device scannedDevice) async {
    if (_deviceController.isClosed) return;

    try {
      print('Connecting to QR device: ${scannedDevice.name} at ${scannedDevice.ip}');
      
      // Initialize connection
      await _initializeNetwork(scannedDevice.ip);
      
      // Add scanned device to stream
      _deviceController.add(scannedDevice);
      
      // Get current device info
      String? ip = await _getNetworkIP();
      if (ip == null || ip.isEmpty) {
        ip = await NetworkInfo().getWifiIP();
      }

      // Create current device info
      final myDevice = Device(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _profile.name,
        ip: ip ?? '0.0.0.0',
        port: udpPort,
        profile: _profile,
      );

      // Broadcast presence to scanned device
      final data = utf8.encode(jsonEncode(myDevice.toJson()));
      await _sender?.send(
        data,
        Endpoint.unicast(
          InternetAddress(scannedDevice.ip),
          port: Port(udpPort)
        )
      );
      
      print('QR Connection established with: ${scannedDevice.name}');
    } catch (e) {
      print('Error in QR connection: $e');
      rethrow;
    }
  }

  Future<Device> generateQRDevice() async {
    if (_profile == null) {
      throw Exception('Profile not initialized');
    }

    String? ip = await NetworkInfo().getWifiIP();  // Try getting WiFi IP first
    print('Got WiFi IP: $ip');  // Debug log

    if (ip == null || ip.isEmpty) {
      ip = await _getNetworkIP();  // Fallback to network IP
      print('Fallback IP: $ip');  // Debug log
    }

    final device = Device(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _profile.name,
      ip: ip ?? '0.0.0.0',
      port: udpPort,
      profile: _profile,
    );

    print('Generated QR device: ${device.toJson()}');  // Debug log
    return device;
  }

  void dispose() {
    _isListening = false;
    _broadcastTimer?.cancel();
    _discoveryTimeoutTimer?.cancel();
    _discoveryCompleted = true;
    _deviceController.close();
    _sender?.close();
    _receiver?.close();
  }
}

extension on UDP? {
  get isClosed => null;
}