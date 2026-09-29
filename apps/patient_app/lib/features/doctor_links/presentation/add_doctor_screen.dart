import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_texts.dart';
import '../state/doctor_link_controller.dart';
import 'doctor_link_list.dart';

/// Lets a patient request a link using a doctor-issued code.
class AddDoctorScreen extends StatefulWidget {
  const AddDoctorScreen({super.key});

  @override
  State<AddDoctorScreen> createState() => _AddDoctorScreenState();
}

class _AddDoctorScreenState extends State<AddDoctorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  bool _requestSucceeded = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final FormState? form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    final DoctorLinkController links = AppScope.of(context).doctorLinks;
    FocusScope.of(context).unfocus();
    final bool succeeded = await links.request(_codeController.text);
    if (!mounted) {
      return;
    }
    if (succeeded) {
      _codeController.clear();
    }
    setState(() => _requestSucceeded = succeeded);
  }

  @override
  Widget build(BuildContext context) {
    final DoctorLinkController links = AppScope.of(context).doctorLinks;

    return Scaffold(
      appBar: AppBar(title: const Text('Add your doctor')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: links,
          builder: (BuildContext context, Widget? child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: <Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Enter the code provided by your doctor.',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const MutedText(
                        'Your doctor will accept the request before you are connected.',
                      ),
                      const SizedBox(height: 20),
                      Form(
                        key: _formKey,
                        child: AppTextField(
                          label: 'Doctor code',
                          controller: _codeController,
                          hintText: 'ABC123',
                          textCapitalization: TextCapitalization.characters,
                          textInputAction: TextInputAction.done,
                          enabled: !links.isSubmitting,
                          validator: _validateCode,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Request to link',
                        isLoading: links.isSubmitting,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ),
                if (links.errorMessage != null) ...<Widget>[
                  const SizedBox(height: 16),
                  ErrorText(links.errorMessage!),
                ],
                if (_requestSucceeded) ...<Widget>[
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Doctor link requested',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const MutedText(
                          'Waiting for your doctor to accept the connection.',
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                const SectionHeader('Your links'),
                DoctorLinkList(controller: links),
              ],
            );
          },
        ),
      ),
    );
  }

  String? _validateCode(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'Enter the code from your doctor';
    }
    return null;
  }
}
