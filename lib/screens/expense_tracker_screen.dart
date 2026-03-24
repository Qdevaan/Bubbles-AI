import 'package:flutter/material.dart';

class ExpenseTrackerScreen extends StatelessWidget {
  const ExpenseTrackerScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: const Center(
        child: Text('Expense tracking coming soon.'),
      ),
    );
  }
}
