import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

class CameraTab extends StatelessWidget {
  const CameraTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Mjpeg(
        isLive: true,
        error: (context, error, stack) {
          print(error);
          print(stack);
          return Text(error.toString(), style: TextStyle(color: Colors.red));
        },
        // stream: 'http://uk.jokkmokk.jp/photo/nr4/latest.jpg',
        stream: 'http://192.168.1.16:5000/video',
        // stream: 'http://${getLocalIpAddress()}:5000/video',

        timeout: const Duration(seconds: 10),
      ),
    );
  }
}
