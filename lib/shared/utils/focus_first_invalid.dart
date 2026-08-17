import 'package:flutter/material.dart';

/// One field a failed submit may need to send the customer back to.
///
/// The validator is the same function the `TextFormField` was given, so there
/// is one definition of "valid" per field rather than a second copy that drifts.
class FormFieldRef {
  const FormFieldRef({
    required this.focusNode,
    required this.validator,
    this.controller,
  });

  final FocusNode focusNode;

  /// Re-run to find out whether THIS field is the one holding the form up.
  /// `Form.validate()` only reports pass/fail for the form as a whole.
  final String? Function(String?) validator;

  /// The text the validator reads. Null for a field with no text behind it —
  /// a dropdown, a picker — whose validator closes over its own state.
  final TextEditingController? controller;

  bool get isValid => validator(controller?.text) == null;
}

/// Put the keyboard in the first field a rejected submit is complaining about.
///
/// `Form.validate()` paints the red helper text under every failing field but
/// leaves focus where it was — and on a phone the offending field is usually
/// off screen, so the form simply looks like it ignored the button. Pass the
/// fields in the order they are laid out; the first invalid one wins.
///
/// Scrolls before focusing so the field is on screen when the keyboard opens
/// over the bottom half of it.
void focusFirstInvalid(List<FormFieldRef> fields) {
  for (final field in fields) {
    if (field.isValid) continue;

    final context = field.focusNode.context;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
    }
    field.focusNode.requestFocus();
    return;
  }
}
