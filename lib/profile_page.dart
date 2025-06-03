import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Get the current user
    User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('User Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundImage: AssetImage(
                  'assets/avatar.png'), // You can use NetworkImage(user.photoURL ?? default) if available
            ),
            const SizedBox(height: 16),

            Text(
              'Email: ${user?.email ?? "Unknown"}',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'UID: ${user?.uid ?? "Unknown"}',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Email Verified: ${user?.emailVerified ?? false}',
              style: const TextStyle(fontSize: 18),
            ),
            // Add more fields like displayName or phoneNumber if you use them
            // logout logic
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (route) => false);
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
