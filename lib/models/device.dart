import 'profile.dart';

class Device {
  final String id;
  final String name;
  final String ip;
  final int port;
  final Profile profile;

  Device({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.profile,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      name: json['name'],
      ip: json['ip'],
      port: json['port'],
      profile: Profile.fromJson(json['profile']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'profile': profile.toJson(),
    };
  }
}
