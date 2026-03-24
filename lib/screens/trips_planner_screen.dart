import 'package:flutter/material.dart';

class TripsPlannerScreen extends StatelessWidget {
  const TripsPlannerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Planner')),
      body: const Center(
        child: Text('Trips planning coming soon.'),
      ),
    );
  }
}
