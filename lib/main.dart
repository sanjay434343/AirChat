import 'package:flutter/material.dart';
import 'screens/profile_setup.dart';
import 'screens/home_page.dart';
import 'services/profile_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Clear Flutter image cache on app startup
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Color(0xFF617CFF),    // Light blue
          secondary: Color(0xFF352FED),   // Dark blue
          surface: Colors.white,
          background: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF352FED),   // Dark blue for text
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final savedProfile = await ProfileStorage.getProfile();
      if (!mounted) return;

      if (savedProfile != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ChatHomePage(profile: savedProfile)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
        );
      }
    } catch (e) {
      print('Error checking profile: $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/icon.png',
                width: 80,
              ),
              const SizedBox(height: 20),
              Text(
                'AirChat',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Peer-to-Peer Messaging',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
