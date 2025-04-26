import 'package:airchat/screens/profile_setup.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import '../services/network_service.dart';
import '../models/device.dart';
import '../models/profile.dart';
import '../utils/profile_icons.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:animations/animations.dart';
import 'chat_screen.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/qr_display_dialog.dart';
import '../services/network_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/qr_service.dart';

class ChatHomePage extends StatefulWidget {
  final Profile profile;
  const ChatHomePage({super.key, required this.profile});
  
  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  final NetworkService _networkService = NetworkService();
  final List<Device> _devices = [];
  final Map<String, Device> _deviceMap = {};
  bool _isInitializing = true;
  String? _error;
  String? _wifiName;
  Timer? _wifiCheckTimer;
  Timer? _discoveryTimeoutTimer;  // Add this line
  final Map<String, DateTime> _lastSeen = {};
  Timer? _deviceCleanupTimer;
  static const Duration _offlineThreshold = Duration(seconds: 10);
  Device? _myQRDevice;

  @override
  void initState() {
    super.initState();
    _deviceCleanupTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _checkDevicesOnline();
    });
    _setupNetwork();

    // Listen for new device connections
    _networkService.deviceStream.listen((device) {
      print('New device received: ${device.name}');
      if (!_deviceMap.containsKey(device.ip)) {
        _handleNewConnection(device);
      }
    });
  }

  Future<void> _setupNetwork() async {
    await _networkService.startDiscovery(widget.profile);
    await _generateQRDevice();
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request all required permissions for both Android versions
    final permissions = [
      Permission.location,
      Permission.nearbyWifiDevices,
      Permission.notification,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.photos,
      Permission.camera,
    ];

    // Request each permission individually for better control
    for (var permission in permissions) {
      final status = await permission.request();
      if (!status.isGranted) {
        print('${permission.toString()} is not granted');
      }
    }

    // Check if essential permissions are granted
    final locationStatus = await Permission.location.status;
    final wifiStatus = await Permission.nearbyWifiDevices.status;

    if (locationStatus.isGranted && (wifiStatus.isGranted || await _isAndroid12OrBelow())) {
      await _generateQRDevice(); // Generate QR first
      _initializeNetwork();
      _setupWifiMonitoring();
    } else {
      setState(() => _error = 'Essential permissions are not granted');
    }
  }

  Future<bool> _isAndroid12OrBelow() async {
    if (Theme.of(context).platform != TargetPlatform.android) return false;
    return int.parse(await Connectivity().getAndroidApiLevel()) <= 31; // Android 12 is API 31
  }

  void _setupWifiMonitoring() {
    _getWifiInfo(); // Initial check

    // Setup periodic check
    _wifiCheckTimer?.cancel();
    _wifiCheckTimer = Timer.periodic(Duration(seconds: 3), (_) async {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.wifi) {
        _getWifiInfo();
      } else {
        setState(() {
          _wifiName = null;
          _error = 'Please connect to WiFi';
        });
      }
    });
  }

  Future<void> _initializeNetwork() async {
    try {
      await _networkService.startDiscovery(widget.profile);
      _networkService.deviceStream.listen(
        (device) {
          setState(() {
            _lastSeen[device.ip] = DateTime.now();
            _deviceMap[device.ip] = device;
            _updateDevicesList();
          });
        },
        onError: (error) {
          print('Network error: $error');
        },
      );
    } catch (e) {
      print('Error initializing network: $e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  void _updateDevicesList() {
    final now = DateTime.now();
    setState(() {
      _devices.clear();
      _deviceMap.forEach((ip, device) {
        final lastSeen = _lastSeen[ip];
        if (lastSeen != null && now.difference(lastSeen) <= _offlineThreshold) {
          _devices.add(device);
        }
      });
    });
  }

  void _checkDevicesOnline() {
    final now = DateTime.now();
    setState(() {
      _deviceMap.forEach((ip, device) {
        // Only update state if device status would change
        final lastSeen = _lastSeen[ip];
        if (lastSeen != null) {
          final isOffline = now.difference(lastSeen) > _offlineThreshold;
          if (isOffline && _devices.contains(device)) {
            _devices.remove(device);
          } else if (!isOffline && !_devices.contains(device)) {
            _devices.add(device);
          }
        }
      });
    });
  }

  Future<void> _getWifiInfo() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.wifi) {
        setState(() {
          _wifiName = null;
          _error = 'Please connect to WiFi';
        });
        return;
      }

      final info = NetworkInfo();
      final wifiName = await info.getWifiName();
      final wifiIP = await info.getWifiIP();
      
      if (!mounted) return;

      setState(() {
        _wifiName = wifiName?.replaceAll('"', '');
        if (_wifiName == null || wifiIP == null) {
          _error = 'Please connect to a WiFi network';
          _devices.clear();
        } else {
          _error = null;
        }
      });

      // If we have valid WiFi, ensure network service is running
      if (_wifiName != null && _error == null) {
        _initializeNetwork();
      }
    } catch (e) {
      print('Error getting WiFi info: $e');
      setState(() {
        _error = 'WiFi error: $e';
        _wifiName = null;
      });
    }
  }

  Future<void> _generateQRDevice() async {
    try {
      final device = await _networkService.generateQRDevice();
      print('Generated QR device: ${device.toJson()}'); // Debug print
      
      if (!mounted) return;
      
      setState(() {
        _myQRDevice = device;
      });
    } catch (e) {
      print('Error generating QR code: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate QR code: $e')),
      );
    }
  }

  void _showQRScanner() {
    bool isProcessing = false;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => QRScannerDialog(
        onDeviceScanned: (scannedDevice) async {
          // Prevent multiple connections
          if (isProcessing) return;
          isProcessing = true;

          try {
            // First close the scanner dialog
            Navigator.pop(context);

            // Don't connect if scanning own QR code
            if (scannedDevice.profile.name == widget.profile.name) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cannot connect to yourself')),
              );
              return;
            }

            // Check if already connected
            if (_deviceMap.containsKey(scannedDevice.ip)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Already connected to this device')),
              );
              return;
            }

            // Connect via QR
            await _networkService.connectViaQR(scannedDevice);
            
            // Handle connection and navigation
            _handleNewConnection(scannedDevice);
            
          } catch (e) {
            print('QR scan error: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to connect: $e')),
            );
          } finally {
            isProcessing = false;
          }
        },
        myProfile: widget.profile,
      ),
    );
  }

  void _handleNewConnection(Device device) async {
    try {
      // Don't connect to self
      if (device.profile.name == widget.profile.name) {
        print('Avoiding self-connection');
        return;
      }

      setState(() {
        _lastSeen[device.ip] = DateTime.now();
        _deviceMap[device.ip] = device;
        _updateDevicesList();
        _isInitializing = false;
      });

      // Navigate to chat screen
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              peerDevice: device,
              isServer: widget.profile.name.compareTo(device.profile.name) < 0,
              isSender: true, // Set to true since we're initiating the chat
            ),
          ),
        );
      }
    } catch (e) {
      print('Connection handling error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AirChat',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              'Nearby Devices',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code_scanner),
            onPressed: _showQRScanner,
            tooltip: 'Scan QR Code',
          ),
          // Remove QR code generation button for older devices
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.secondary,
                ],
              ),
            ),
            child: PopupMenuButton<String>(
              icon: CircleAvatar(
                backgroundColor: Colors.transparent,
                child: ProfileIcons.getGenderIcon(
                  widget.profile.gender,
                  color: Colors.white,
                ),
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileSetupPage(
                        initialProfile: widget.profile,
                        isEditing: true,
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Edit Profile'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_deviceMap.isEmpty) ...[
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 24),
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildQRCode(),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showQRScanner,
                        icon: Icon(Icons.qr_code_scanner),
                        label: Text('Scan to Connect'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _deviceMap.length,
                  itemBuilder: (context, index) {
                    final device = _deviceMap.values.elementAt(index);
                    final lastSeen = _lastSeen[device.ip];
                    final isOnline = lastSeen != null &&
                        DateTime.now().difference(lastSeen) <= _offlineThreshold;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: OpenContainer(
                        transitionType: ContainerTransitionType.fadeThrough,
                        openBuilder: (context, _) => ChatScreen(
                          peerDevice: device,
                          isServer: widget.profile.name.compareTo(device.profile.name) < 0,
                          isSender: widget.profile.name.compareTo(device.profile.name) < 0, // Updated to a bool value
                        ),
                        closedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        closedElevation: 0,
                        closedColor: Theme.of(context).colorScheme.surface,
                        closedBuilder: (context, openContainer) => ListTile(
                          enabled: isOnline,
                          onTap: isOnline ? openContainer : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tileColor: isOnline
                              ? Theme.of(context).colorScheme.surface
                              : Theme.of(context).colorScheme.surfaceVariant,
                          leading: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(context).colorScheme.secondary,
                                    ],
                                  ),
                                ),
                                child: CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  child: ProfileIcons.getGenderIcon(
                                    device.profile.gender,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green : Colors.grey,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            device.profile.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isOnline
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          subtitle: Text(
                            isOnline ? 'Online' : 'Last seen: ${_formatLastSeen(lastSeen)}',
                            style: TextStyle(
                              color: isOnline
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQRCode() {
    if (_myQRDevice == null) {
      return Container(
        height: 200,
        width: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16),
            Text(
              'Generating QR Code...',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            ),
          ),
          child: QrImageView(
            data: QRService.generateQRData(_myQRDevice!),
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            gapless: true,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Your IP: ${_myQRDevice!.ip}',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Never';
    final difference = DateTime.now().difference(lastSeen);
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  @override
  void dispose() {
    _deviceCleanupTimer?.cancel();
    _wifiCheckTimer?.cancel();
    _discoveryTimeoutTimer?.cancel();  // Add this line
    _networkService.dispose();
    super.dispose();
  }
}

extension on Connectivity {
  getAndroidApiLevel() {}
}
