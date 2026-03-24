import 'package:flutter/material.dart';

class HealthDashboardScreen extends StatelessWidget {
  const HealthDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Metrics')),
      body: const Center(
        child: Text('Health Dashboard coming soon.'),
      ),
    );
  }
}
