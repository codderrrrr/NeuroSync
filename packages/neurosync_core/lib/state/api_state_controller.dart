import 'package:flutter/foundation.dart';

import '../network/api_exception.dart';

/// The state, and the try/catch, that every controller talking to the API
/// needs.
///
/// A controller that reads from the API and one that writes to it both need
/// the same three things: a flag saying a request is in flight, the message
/// when it failed, and a rule that an API failure is reported rather than
/// thrown. Stating them once means a new controller cannot get the error
/// handling subtly wrong.
mixin ApiStateController on ChangeNotifier {
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  /// Whether a read is in flight.
  bool get isLoading => _isLoading;

  /// Whether a write is in flight.
  bool get isSubmitting => _isSubmitting;

  /// The last API failure, or null when there has not been one.
  String? get errorMessage => _errorMessage;

  /// Runs a read, surfacing an API failure without losing what is on screen.
  ///
  /// A failed refresh keeps the previous data and shows the message, so a
  /// network blip never blanks a screen the patient was reading.
  ///
  /// [onError] handles a failure the caller expects and wants to answer
  /// itself, such as a 404 that means "there is nothing here yet" rather than
  /// "something went wrong". Without one, the failure becomes the error
  /// message.
  Future<void> runLoad(
    Future<void> Function() action, {
    void Function(ApiException error)? onError,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (error) {
      if (onError != null) {
        onError(error);
      } else {
        _errorMessage = error.message;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Runs a write, reporting whether it succeeded.
  ///
  /// An API failure is reported through [errorMessage] and the write reports
  /// false, rather than throwing into the widget that asked for it.
  Future<bool> runSubmit(Future<void> Function() action) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
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
  Future<T?> runSubmitValue<T>(Future<T?> Function() action) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action();
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Clears the error message, if there is one.
  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Reports a failure that did not come from the API.
  ///
  /// A controller that rejects its own input before making a request uses
  /// this, so the message reaches the screen the same way an API failure
  /// does.
  void reportError(String message) {
    _errorMessage = message;
    notifyListeners();
  }
}
