import 'dart:convert';
import '../models/device.dart';

class QRService {
  static String generateQRData(Device device) {
    final Map<String, dynamic> qrData = {
      'id': device.id,
      'name': device.name,
      'ip': device.ip,
      'port': device.port,
      'profile': device.profile.toJson(),
    };
    return jsonEncode(qrData);
  }

  static Device? parseQRData(String qrData) {
    try {
      final Map<String, dynamic> data = jsonDecode(qrData);
      return Device.fromJson(data);
    } catch (e) {
      print('Error parsing QR data: $e');
      return null;
    }
  }
}
