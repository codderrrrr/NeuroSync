import 'package:flutter/material.dart';

import '../network/api_exception.dart';

/// The state, and the try/catch, that every controller talking to the API
/// needs.
///
/// A controller that reads from the API and one that writes to it both need
/// the same three things: a flag saying a request is in flight, the message
/// when it failed, and a rule that an API failure is reported rather than
/// thrown.
///
/// A controller that reads more than one thing needs more than one message:
/// a history that will not load must not blank the error of a plan that
/// will. Each read therefore writes to its own named slot, and the default
/// slot is the controller's main one.
mixin ApiStateController on ChangeNotifier {
  /// The slot a controller's main read writes to.
  static const String defaultSlot = 'default';

  bool _isLoading = false;
  bool _isSubmitting = false;
  final Map<String, String?> _errors = <String, String?>{};

  /// Whether a read is in flight.
  bool get isLoading => _isLoading;

  /// Whether a write is in flight.
  bool get isSubmitting => _isSubmitting;

  /// The last failure of the controller's main read.
  String? get errorMessage => _errors[defaultSlot];

  /// The last failure of one named read.
  String? errorFor(String slot) => _errors[slot];

  /// Runs a read, surfacing an API failure without losing what is on screen.
  ///
  /// A failed refresh keeps the previous data and shows the message, so a
  /// network blip never blanks a screen the patient was reading.
  ///
  /// [onError] handles a failure the caller expects and wants to answer
  /// itself, such as a 404 that means "there is nothing here yet" rather than
  /// "something went wrong". Without one, the failure becomes the error
  /// message for [slot].
  Future<void> runLoad(
    Future<void> Function() action, {
    String slot = defaultSlot,
    void Function(ApiException error)? onError,
  }) async {
    _isLoading = true;
    _errors[slot] = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (error) {
      if (onError != null) {
        onError(error);
      } else {
        _errors[slot] = error.message;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Runs a write, reporting whether it succeeded.
  ///
  /// An API failure is reported through the error message and the write
  /// reports false, rather than throwing into the widget that asked for it.
  Future<bool> runSubmit(
    Future<void> Function() action, {
    String slot = defaultSlot,
  }) async {
    _isSubmitting = true;
    _errors[slot] = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (error) {
      _errors[slot] = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Runs a write that produces a value, reporting null when it fails.
  ///
  /// For a write whose result is the point of the call, so a failure is
  /// reported as no result rather than as no result *and* a failure.
  Future<T?> runSubmitValue<T>(
    Future<T?> Function() action, {
    String slot = defaultSlot,
  }) async {
    _isSubmitting = true;
    _errors[slot] = null;
    notifyListeners();
    try {
      return await action();
    } on ApiException catch (error) {
      _errors[slot] = error.message;
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Clears the error message, if there is one.
  void clearError({String slot = defaultSlot}) {
    if (_errors[slot] == null) {
      return;
    }
    _errors[slot] = null;
    notifyListeners();
  }

  /// Reports a failure that did not come from the API.
  ///
  /// A controller that rejects its own input before making a request uses
  /// this, so the message reaches the screen the same way an API failure
  /// does.
  void reportError(String message, {String slot = defaultSlot}) {
    _errors[slot] = message;
    notifyListeners();
  }
}
