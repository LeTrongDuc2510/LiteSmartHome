import 'package:flutter/material.dart';

class SwitchesTab extends StatefulWidget {
  const SwitchesTab({super.key});

  @override
  State<SwitchesTab> createState() => _SwitchesTabState();
}

class _SwitchesTabState extends State<SwitchesTab> {
  bool _isSwitched = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enable feature'),
          Switch(
            value: _isSwitched,
            onChanged: (bool value) {
              setState(() {
                _isSwitched = value;
              });
            },
          ),
        ],
      ),
    );
  }
}
