import 'package:flutter/material.dart';

/// Labelled text field matching the card-based visual style.
///
/// The label sits above the box and scrolls with it, so a scrolled form never
/// leaves a label orphaned above an unrelated field.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.autocorrect,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;

  /// Null falls back to correction for prose and no correction for secrets:
  /// a name benefits from correction, an email or password never does.
  final bool? autocorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _Field(
          controller: controller,
          hintText: hintText,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          autofillHints: autofillHints,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          enabled: enabled,
          autofocus: autofocus,
          autocorrect: autocorrect,
        ),
      ],
    );
  }
}

/// A text box, with a reveal control when it holds a secret.
class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.obscureText,
    required this.enabled,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.autocorrect,
  });

  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;
  final bool? autocorrect;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final bool secret = widget.obscureText;
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: secret && !_revealed,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      autocorrect: widget.autocorrect ?? !secret,
      decoration: InputDecoration(
        hintText: widget.hintText,
        // A secret the patient cannot check is a secret they will mistype.
        suffixIcon: secret
            ? IconButton(
                icon: Icon(
                  _revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                tooltip: _revealed ? 'Hide password' : 'Show password',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _revealed = !_revealed),
              )
            : null,
      ),
    );
  }
}
