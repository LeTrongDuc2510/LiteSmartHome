import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'login_page.dart';
import 'register_page.dart';
import 'profile_page.dart';
import 'stats_page.dart';
import 'stats_temp_page.dart';
import 'camera_view.dart';
import 'buttons_page_test.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Auth Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const MyHomePage(title: 'Home Page'),
        '/profile': (context) => const ProfilePage(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // number of tabs
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/profile');
                },
                child: const CircleAvatar(
                  backgroundImage: AssetImage('assets/avatar.png'),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: "Humidity"),
              Tab(text: "Temperature"),
              Tab(text: "Switches"),
              Tab(text: "Camera"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            StatsTab(),
            TempStatsTab(),
            SwitchesTestTab(),
            CameraTab(),
          ],
        ),
        // floatingActionButton: FloatingActionButton(
        //   onPressed: _incrementCounter,
        //   tooltip: 'Increment',
        //   child: const Icon(Icons.add),
        // ),
      ),
    );
  }
}
