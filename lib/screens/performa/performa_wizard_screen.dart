import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/providers/persona_provider.dart';

import 'draft.dart';
import 'widgets/step1_identity.dart';
import 'widgets/step2_language.dart';
import 'widgets/step3_goals.dart';

/// Three-step persona wizard ("Performa"). Collects identity, language,
/// and goal information then upserts via [PersonaProvider]. The wizard
/// hard-blocks back navigation: persona setup is mandatory before the
/// rest of the app is reachable (Task 18 wires the auth-gate redirect).
class PerformaWizardScreen extends StatefulWidget {
  const PerformaWizardScreen({super.key});

  @override
  State<PerformaWizardScreen> createState() => _PerformaWizardScreenState();
}

class _PerformaWizardScreenState extends State<PerformaWizardScreen> {
  int _step = 0;
  final _draft = PerformaDraft();
  bool _submitting = false;

  static const _titles = ['About you', 'Language & style', 'Goals & context'];

  bool get _canAdvance {
    if (_step == 0) return _draft.rolePrimary != null;
    if (_step == 1) {
      return (_draft.nativeLanguage ?? '').isNotEmpty &&
          (_draft.learningLanguage ?? '').isNotEmpty;
    }
    return true;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await context.read<PersonaProvider>().upsert(_draft.toUpdate());
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onStepChanged() => setState(() {});

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return Step1Identity(draft: _draft, onChanged: _onStepChanged);
      case 1:
        return Step2Language(draft: _draft, onChanged: _onStepChanged);
      default:
        return Step3Goals(draft: _draft, onChanged: _onStepChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // hard block: persona setup must complete
      child: Scaffold(
        appBar: AppBar(title: Text(_titles[_step])),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LinearProgressIndicator(value: (_step + 1) / 3),
              const SizedBox(height: 16),
              Expanded(child: _buildStepBody()),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed:
                          _submitting ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: !_canAdvance || _submitting
                        ? null
                        : () {
                            if (_step < 2) {
                              setState(() => _step++);
                            } else {
                              _submit();
                            }
                          },
                    child: Text(_step < 2 ? 'Next' : 'Finish'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
