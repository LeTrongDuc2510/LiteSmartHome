import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

const broker = 'app.coreiot.io';
const port = 1883;
const clientId = 'IOT_DEVICE_1';
const accessToken = 'liBRzHuTDetPGOZ8thrk';

final telemetryTopic = 'v1/devices/me/telemetry';
final rpcRequestTopic = 'v1/devices/me/rpc/request/+';
final attributeResponseTopic = 'v1/devices/me/attributes';

late MqttServerClient client;

Future<void> setupMqtt() async {
  client = MqttServerClient(broker, clientId);
  client.port = port;
  client.keepAlivePeriod = 20;
  client.logging(on: true);
  client.setProtocolV311();
  client.secure = false;
  client.onDisconnected = onDisconnected;
  client.onConnected = onConnected;
  client.onSubscribed = onSubscribed;

  final connMessage = MqttConnectMessage()
      .withClientIdentifier(clientId)
      .authenticateAs(accessToken, '') // username only
      .startClean()
      .withWillQos(MqttQos.atLeastOnce);

  client.connectionMessage = connMessage;

  try {
    await client.connect();
  } catch (e) {
    print('Connection failed: $e');
    client.disconnect();
  }

  client.subscribe(attributeResponseTopic, MqttQos.atMostOnce);

  client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
    final recMess = c[0].payload as MqttPublishMessage;
    final payload =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    print('Received on ${c[0].topic}: $payload');
    final jsonObj = json.decode(payload);

    if (jsonObj.containsKey('value')) {
      final value = jsonObj['value'];
      print('Received value: $value');
    }
  });
}

Future<void> _connectToMQTT() async {
  client = MqttServerClient(broker, clientId);
  client.port = 1883;
  client.logging(on: true);
  client.keepAlivePeriod = 20;
  client.onConnected = () {
    print('Connected to MQTT broker');
    client.subscribe(rpcRequestTopic, MqttQos.atMostOnce);
  };
  client.onDisconnected = () => print('Disconnected from MQTT');
  client.onSubscribed = (String topic) => print('Subscribed to $topic');

  // client.connectionMessage = MqttConnectMessage()
  //     .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
  //     .authenticateAs(jwtToken, '') // JWT as username, blank password
  //     .startClean();
  client.connectionMessage = MqttConnectMessage()
      .authenticateAs(accessToken, null) // username only
      .startClean()
      .withWillQos(MqttQos.atLeastOnce);

  try {
    await client.connect();
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      final recMess = messages[0].payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('MQTT Message: $payload');

      final data = json.decode(payload);
      if (data.containsKey('value')) {
        final bool updatedValue = data['value'] == true;
        print('Received value: $updatedValue');
      }
    });
  } catch (e) {
    print('MQTT connection failed: $e');
    client.disconnect();
  }
}

void onConnected() => print('Connected successfully');
void onDisconnected() => print('Disconnected');
void onSubscribed(String topic) => print('Subscribed to $topic');

void startTelemetryLoop() {
  int temp = 30;
  int humi = 50;
  int light = 100;
  const double lat = 10.880018410410052;
  const double long = 106.80633605864662;

  Timer.periodic(Duration(seconds: 5), (timer) {
    final data = {
      'temperature': temp++,
      'humidity': humi++,
      'light': light++,
      'lat': lat,
      'long': long,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(json.encode(data));
    client.publishMessage(
        telemetryTopic, MqttQos.atLeastOnce, builder.payload!);
    print('Published telemetry: $data');
  });
}

void main() async {
  print('Hello Core IOT');
  // await setupMqtt();
  await _connectToMQTT();
  // startTelemetryLoop();
}
