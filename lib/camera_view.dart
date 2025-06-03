import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:flutter/services.dart' show rootBundle;

class CameraTab extends StatelessWidget {
  const CameraTab({super.key});

  Future<String> getLocalIpFromJson() async {
    final jsonString = await rootBundle.loadString('assets/token.json');
    final data = jsonDecode(jsonString);
    return data['local_ip'];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: getLocalIpFromJson(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Text("Error loading IP",
              style: TextStyle(color: Colors.red));
        }

        final ip = snapshot.data!;
        final url = 'http://$ip:5000/video';

        return Center(
          child: Mjpeg(
            isLive: true,
            error: (context, error, stack) {
              print(error);
              print(stack);
              return Text(error.toString(),
                  style: TextStyle(color: Colors.red));
            },
            stream: url,
            timeout: const Duration(seconds: 20),
          ),
        );
      },
    );
  }
}
