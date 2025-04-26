import 'package:flutter/material.dart';
import '../models/profile.dart';

class ProfileIcons {
  static Icon getGenderIcon(Gender gender, {double size = 24, Color? color}) {
    return Icon(
      gender == Gender.male 
          ? Icons.face 
          : Icons.face_3,
      size: size,
      color: color,
    );
  }
}
