enum Gender { male, female }

class Profile {
  final String name;
  final Gender gender;
  String? _ip;

  Profile({required this.name, required this.gender});

  Map<String, dynamic> toJson() => {
    'name': name,
    'gender': gender.index,
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    name: json['name'],
    gender: Gender.values[json['gender']],
  );

  String get ip => _ip ?? '0.0.0.0';
  set ip(String value) => _ip = value;
}
