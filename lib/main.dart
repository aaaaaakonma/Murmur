import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/p2p_chat_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseInitialized = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseInitialized = true;
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Notification service notice: $e');
  }

  runApp(BoredP2PChatApp(firebaseInitialized: firebaseInitialized));
}

class BoredP2PChatApp extends StatefulWidget {
  final bool firebaseInitialized;

  const BoredP2PChatApp({super.key, required this.firebaseInitialized});

  @override
  State<BoredP2PChatApp> createState() => _BoredP2PChatAppState();
}

class _BoredP2PChatAppState extends State<BoredP2PChatApp> {
  late final P2PChatService _chatService;

  @override
  void initState() {
    super.initState();
    _chatService = P2PChatService();
  }

  @override
  void dispose() {
    _chatService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MURMUR — Ingress Keys & Gateway Addresses',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          secondary: Color(0xFFC6C5CF),
          surface: Color(0xFF101013),
          error: Color(0xFFF87171),
        ),
        useMaterial3: true,
        fontFamily: 'Geist',
      ),
      home: HomeScreen(chatService: _chatService),
    );
  }
}
