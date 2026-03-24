import 'package:flutter/material.dart';

class SmartHomeDashboardScreen extends StatelessWidget {
  const SmartHomeDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Home Dashboard')),
      body: const Center(
        child: Text('IoT Devices coming soon.'),
      ),
    );
  }
}
