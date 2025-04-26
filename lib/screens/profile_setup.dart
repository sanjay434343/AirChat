import 'package:airchat/screens/home_page.dart';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../utils/profile_icons.dart';
import '../services/profile_storage.dart';

class ProfileSetupPage extends StatefulWidget {
  final Profile? initialProfile;
  final bool isEditing;

  const ProfileSetupPage({
    super.key, 
    this.initialProfile,
    this.isEditing = false,
  });

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _nameController = TextEditingController();
  Gender _selectedGender = Gender.male;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _nameController.text = widget.initialProfile!.name;
      _selectedGender = widget.initialProfile!.gender;
    }
  }

  void _saveAndContinue() async {
    if (_formKey.currentState!.validate()) {
      final profile = Profile(
        name: _nameController.text,
        gender: _selectedGender,
      );
      
      // Save profile to storage
      await ProfileStorage.saveProfile(profile);
      
      if (widget.isEditing) {
        Navigator.pop(context, profile);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatHomePage(profile: profile),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    setState(() {
                      _selectedGender = _selectedGender == Gender.male 
                          ? Gender.female 
                          : Gender.male;
                    });
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: CircleAvatar(
                      key: ValueKey(_selectedGender),
                      radius: 60,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: ProfileIcons.getGenderIcon(
                        _selectedGender,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Swipe to change gender',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saveAndContinue,
                  child: Text(widget.isEditing ? 'Save' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
