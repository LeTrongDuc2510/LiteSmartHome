import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';

class SwitchesTestTab extends StatefulWidget {
  const SwitchesTestTab({super.key});

  @override
  State<SwitchesTestTab> createState() => _SwitchesTabState();
}

class _SwitchesTabState extends State<SwitchesTestTab> {
  bool _isSwitched = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    _getSwitchState(); // fetch initial state
    _pollingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _getSwitchState();
    });
  }

  void printSwitchState() {
    print('Switch is ${_isSwitched ? "ON" : "OFF"}');
  }

  Future<void> _postSwitchState() async {
    final String tokenJson = await rootBundle.loadString('assets/token.json');
    final Map<String, dynamic> tokenData = json.decode(tokenJson);
    final String jwtToken = tokenData['jwtToken'];
    final String entityId = tokenData['device_id'];

    final Uri url = Uri.https(
      'app.coreiot.io',
      '/api/rpc/oneway/$entityId',
    );

    // Prepare the request body

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Authorization': 'Bearer $jwtToken',
      },
      body:
          '{"method":"setServoAngle","params":$_isSwitched,"persistent":false,"timeout":500}',
    );

    if (response.statusCode == 200) {
      print('Switch state posted successfully');
    } else {
      print('Failed to post switch state: ${response.statusCode}');
    }
  }

  Future<void> _getSwitchState() async {
    final String tokenJson = await rootBundle.loadString('assets/token.json');
    final Map<String, dynamic> tokenData = json.decode(tokenJson);
    final String jwtToken = tokenData['jwtToken'];

    const String entityId = 'p1qlDfa1BFXAMjyqU8OS';

    final Uri url = Uri.https(
      'app.coreiot.io',
      '/api/v1/$entityId/attributes',
      {
        'clientKeys': 'value',
        'sharedKeys': 'configuration'
      }, // Assuming 'value' is the key for the switch state
    );

    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-Authorization': 'Bearer $jwtToken',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      bool newSwitchState = data['client']['value'];
      // if (newSwitchState != _isSwitched) {
      if (mounted && newSwitchState != _isSwitched) {
        setState(() {
          _isSwitched = newSwitchState;
        });
        print('Switch state updated to: $_isSwitched');
      } else {
        print('Switch state unchanged');
      }
    } else {
      print('Failed to fetch switch state: ${response.statusCode}');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Door Switch:'),
          Switch(
            value: _isSwitched,
            onChanged: (bool value) {
              setState(() {
                _isSwitched = value;
                printSwitchState();
                _postSwitchState();
              });
            },
          ),
          const SizedBox(width: 20),
          const Text('Current State:'),
          Text(
            _isSwitched ? 'OPEN' : 'CLOSED',
            style: TextStyle(
              color: _isSwitched ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

void onConnected() {
  print('Connected successfully!!');
}

void onDisconnected() {
  print('Disconnected');
}

void onSubscribed(String topic) {
  print('Subscribed to $topic');
}
