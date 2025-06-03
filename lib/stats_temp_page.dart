import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class TempStatsTab extends StatefulWidget {
  const TempStatsTab({super.key});

  @override
  State<TempStatsTab> createState() => _TempStatsTabState();
}

class _TempStatsTabState extends State<TempStatsTab> {
  String _result = 'Loading...';

  // DateTime _startTs_df = DateTime.now();
  DateTime _startTs_df =
      DateTime.now().subtract(const Duration(hours: 12)); // for testing purpose
  DateTime _endTs_df = DateTime.now().add(const Duration(hours: 24));
  late List<FlSpot> humiditySpots = [];
  late List<FlSpot> predictedHumiditySpots = [];
  bool _validDate = true;
  final int interval = 900000; // Example interval in milliseconds - 15 minutes
  final int numPoints = 12; // Number of points to display
  late int numPredPoints;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      _validDate = true;
      final String tokenJson = await rootBundle.loadString('assets/token.json');
      final Map<String, dynamic> tokenData = json.decode(tokenJson);
      final String jwtToken = tokenData['jwtToken'];

      const String entityType = 'DEVICE';
      final String entityId = tokenData['device_id'];
      // const String entityId =  '1f7287c0-3b99-11f0-aae0-0f85903b3644'; // device Hao
      const List<String> keys = ['temperature'];
      const int limit = 10000;
      const bool useStrictDataTypes = false;
      // const int limit_display = 8; // number of display point

      final int startTs = _startTs_df.millisecondsSinceEpoch;
      final int endTs = _endTs_df.millisecondsSinceEpoch;

      final Uri url = Uri.https(
        'app.coreiot.io',
        '/api/plugins/telemetry/$entityType/$entityId/values/timeseries',
        {
          'keys': keys.join(','),
          'startTs': startTs.toString(),
          'endTs': endTs.toString(),
          // 'interval': interval.toString(),
          'limit': limit.toString(),
          'useStrictDataTypes': useStrictDataTypes.toString(),
        },
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        debugPrint('Response: ${response.body}');
        final body = response.body;

        final Map<String, dynamic> data = jsonDecode(body);
        final rawHumiditySpots = parseHumiditySpots(data);
        // debugPrint('Raw Humidity Spots: $rawHumiditySpots');
        final newHumiditySpots = filterByInterval(rawHumiditySpots, interval);
        debugPrint('Filtered Humidity Spots : $newHumiditySpots');
        debugPrint('Parsed Humidity Spots: $newHumiditySpots');
        final DateTime lastRealTs = DateTime.fromMillisecondsSinceEpoch(
            data['temperature'].first['ts']);

        // fetch predictions outside setState
        final preds = await _fetchPredictions(lastRealTs, newHumiditySpots);
        debugPrint('Predictions: $preds');

        setState(() {
          _result = body;
          humiditySpots = newHumiditySpots;
          predictedHumiditySpots = preds;
        });

        debugPrint('Temperature Spots: $humiditySpots');
        debugPrint('Predicted Temperature Spots: $predictedHumiditySpots');
      } else {
        setState(() {
          _result = 'Error: ${response.statusCode}\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _result = 'Exception: $e';
      });
    }
  }

  Future<List<FlSpot>> _fetchPredictions(
      DateTime lastTs, List<FlSpot> realSpot) async {
    debugPrint('Fetching predictions for last timestamp: $lastTs');
    final String tokenJson = await rootBundle.loadString('assets/token.json');
    final Map<String, dynamic> tokenData = json.decode(tokenJson);
    final String localIp = tokenData['local_ip'];
    final Uri url =
        Uri.parse('http://$localIp:5000/pred_stats'); // change this to your API
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      debugPrint('Prediction Data: $data');
      final List<dynamic> predHumidity = data['pred_temp_list'];
      // take only the first 5 predictions
      // if (predHumidity.length > ) {
      debugPrint('Number of Predictions: ${numPredPoints}');
      predHumidity.removeRange(numPredPoints, predHumidity.length);
      // }

      List<FlSpot> predictedSpots = [];

      final FlSpot lastRealSpot = realSpot.last;
      debugPrint('Last Real Spot: $lastRealSpot');
      predictedSpots.add(lastRealSpot);
      // debugPrint('$predictedSpots');
      debugPrint('Timestamp of last real spot: ${lastRealSpot.x}');

      for (int i = 0; i < predHumidity.length; i++) {
        final double x = lastRealSpot.x + ((i + 1) * (interval / 1000));
        final double y = predHumidity[i].toDouble();
        predictedSpots.add(FlSpot(x, y));
      }
      debugPrint('Predicted Spots: $predictedSpots');

      return predictedSpots;
    } else {
      debugPrint('Prediction API Error: ${response.statusCode}');
      return [];
    }
  }

  Future<void> _pickStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _startTs_df,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_startTs_df),
      );

      if (pickedTime != null) {
        final combinedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() => _startTs_df = combinedDateTime);

        if (_endTs_df.isAfter(combinedDateTime)) {
          _fetchStats();
        } else {
          _validDate = false;
        }
      }
    }
  }

  Future<void> _pickEndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _endTs_df,
      firstDate: _startTs_df,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_endTs_df),
      );

      if (pickedTime != null) {
        final combinedDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() => _endTs_df = combinedDateTime);

        if (combinedDateTime.isAfter(_startTs_df)) {
          _fetchStats();
        } else {
          _validDate = false;
        }
      }
    }
  }

  List<String> pasreDateTime(DateTime dateTime) {
    final List<String> parts = dateTime.toLocal().toString().split(' ');
    if (parts.length < 2) return [dateTime.toLocal().toString(), ''];
    return [parts[0], parts[1]];
  }

  List<FlSpot> parseHumiditySpots(Map<String, dynamic> json) {
    final List<dynamic> humidityData = json['temperature'];

    // Sort humidityData by timestamp ascending (earliest first)
    final sortedData = List<dynamic>.from(humidityData);
    sortedData.sort((a, b) => a['ts'].compareTo(b['ts']));

    final DateTime start =
        DateTime.fromMillisecondsSinceEpoch(sortedData.first['ts']);

    return sortedData.map<FlSpot>((item) {
      final DateTime current = DateTime.fromMillisecondsSinceEpoch(item['ts']);
      final double x = current.difference(start).inSeconds.toDouble();
      final double y = double.parse(item['value']);
      return FlSpot(x, y);
    }).toList();
  }

  List<FlSpot> filterByInterval(List<FlSpot> rawSpots, int intervalMs) {
    if (rawSpots.isEmpty) {
      return [];
    }

    final List<FlSpot> filteredSpots = [];
    final double intervalSeconds = intervalMs / 1000.0;
    const double delta = 50; // 50s in seconds

    for (final spot in rawSpots) {
      double mod = spot.x % intervalSeconds;
      if (mod <= delta) {
        filteredSpots.add(spot);
        // debugPrint(
        //     'Spot: ${spot.x}, Modulus: $mod, Interval: $intervalSeconds, Delta: $delta');
      }
    }

    // Limit the number of spots to the specified limit
    if (filteredSpots.length > numPoints) {
      filteredSpots.removeRange(numPoints, filteredSpots.length);

      // filteredSpots.removeRange(
      // 0, filteredSpots.length - limit); // keep the latest 'limit' spots
    }
    numPredPoints = numPoints - filteredSpots.length;

    return filteredSpots;
  }

  String getFormattedTime(double x) {
    final DateTime time = _startTs_df.add(Duration(seconds: x.toInt()));
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  double calculateBottomTitlesInterval() {
    final double maxChartX = math.max(
      humiditySpots.isNotEmpty ? humiditySpots.last.x : 0,
      predictedHumiditySpots.isNotEmpty ? predictedHumiditySpots.last.x : 0,
    );

    // Adjust these values based on how many labels you want to see
    // and the density you prefer.
    if (maxChartX < 60) {
      // Less than 1 minute: show every 10 seconds
      return 10;
    } else if (maxChartX < 3600) {
      // Less than 1 hour: show every 5 minutes (300 seconds)
      return 300;
    } else if (maxChartX < 86400) {
      // Less than 24 hours: show every hour (3600 seconds)
      return 3600;
    } else {
      // More than 24 hours: show every 6 hours (21600 seconds) or even daily
      return 21600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(
              onPressed: _pickStartDate,
              child: Text('Start: ${pasreDateTime(_startTs_df)[0]}'
                  ' ${pasreDateTime(_startTs_df)[1]}'),
            ),
            ElevatedButton(
              onPressed: _pickEndDate,
              child: Text('End: ${pasreDateTime(_endTs_df)[0]}'
                  ' ${pasreDateTime(_endTs_df)[1]}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Expanded(
        //   child: SingleChildScrollView(
        //     padding: const EdgeInsets.all(16.0),
        //     child: Text(_result),
        //   ),
        // ),
        const SizedBox(height: 16),
        if (humiditySpots.isEmpty)
          const Text('Loading')
        else if (!_validDate)
          const Text(
            'End date must be after start date.',
            style: TextStyle(color: Colors.red),
          )
        else
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Temperature Over Time', // Your chart title here
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              height: 400, // or whatever height you want
              width: MediaQuery.of(context).size.width,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  // maxX: humiditySpots.last.x,
                  maxX: math.max(
                    humiditySpots.isNotEmpty ? humiditySpots.last.x : 0,
                    predictedHumiditySpots.isNotEmpty
                        ? predictedHumiditySpots.last.x
                        : 0,
                  ),
                  minY: [...humiditySpots, ...predictedHumiditySpots]
                          .map((e) => e.y)
                          .reduce((a, b) => a < b ? a : b) -
                      10,
                  maxY: [...humiditySpots, ...predictedHumiditySpots]
                          .map((e) => e.y)
                          .reduce((a, b) => a > b ? a : b) +
                      5,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        // interval: 1,
                        interval: 1800, // 15 minutes in seconds
                        getTitlesWidget: (value, meta) {
                          return Text(getFormattedTime(value));
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true, interval: 5, reservedSize: 30),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: false,
                          reservedSize: 40), // Disable top axis
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: false,
                          reservedSize: 40), // Disable right axis
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: humiditySpots,
                      isCurved: false,
                      color: Colors.blue,
                      barWidth: 3,
                      // belowBarData: BarAreaData(
                      //     show: true, color: Colors.blue.withOpacity(0.3)),
                      dotData: FlDotData(show: true),
                    ),
                    LineChartBarData(
                      spots: predictedHumiditySpots,
                      isCurved: false,
                      color: Colors.red,
                      barWidth: 3,
                      dashArray: [5, 5],
                      // belowBarData: BarAreaData(
                      //     show: true, color: Colors.red.withOpacity(0.3)),
                      dotData: FlDotData(show: true),
                    ),
                  ],
                  borderData: FlBorderData(show: true),
                  gridData: FlGridData(show: true),
                  lineTouchData: LineTouchData(enabled: true),
                ),
              ),
            ),
          ])
      ],
    );
  }
}
