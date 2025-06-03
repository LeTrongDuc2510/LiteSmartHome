import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() async {
  print('Hello Core IOT');

  const broker = 'app.coreiot.io';
  const port = 1883;
  const accessToken = 'liBRzHuTDetPGOZ8thrk';

  final client = MqttServerClient(broker, 'IOT_DEVICE_1');
  client.port = port;
  client.logging(on: false);
  client.keepAlivePeriod = 20;
  client.onConnected = onConnected;
  client.onDisconnected = onDisconnected;
  client.onSubscribed = onSubscribed;

  final connMessage = MqttConnectMessage()
      .authenticateAs(accessToken, null)
      .startClean()
      .withWillQos(MqttQos.atLeastOnce);
  client.connectionMessage = connMessage;

  try {
    await client.connect();
  } catch (e) {
    print('Connection failed: $e');
    client.disconnect();
    return;
  }

  client.subscribe('v1/devices/me/rpc/request/+', MqttQos.atLeastOnce);
  // final tempData = {"clientKeys": "value", "sharedKeys": "value"};
  // final builder = MqttClientPayloadBuilder();
  // builder.addString(json.encode(tempData));
  // client.publishMessage('v1/devices/me/attributes/request/1',
  //     MqttQos.atLeastOnce, builder.payload!);

  client.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
    final recMess = c![0].payload as MqttPublishMessage;
    final payload =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    print('Received: $payload');
    try {
      final jsonObj = json.decode(payload);
      if (jsonObj['method'] == 'setValueButtonLED') {
        final tempData = {'value': jsonObj['params']};
        print('Publish Button LED value: ${tempData['value']}');

        final builder = MqttClientPayloadBuilder();
        builder.addString(json.encode(tempData));
        client.publishMessage(
            'v1/devices/me/attributes', MqttQos.atLeastOnce, builder.payload!);
      }
    } catch (_) {}
  });
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
