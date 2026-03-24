import 'package:flutter/material.dart';

class IntegrationsHubScreen extends StatelessWidget {
  const IntegrationsHubScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations Hub')),
      body: const Center(
        child: Text('API Integrations coming soon.'),
      ),
    );
  }
}
