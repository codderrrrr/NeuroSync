import 'package:flutter/foundation.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../data/exception_repository.dart';
import '../models/review_exception.dart';

/// Loads the doctor's review queue, and records what they decide about it.
///
/// Holds both the queue and any detail opened from it, because a review changes
/// the row the queue is showing: closing an exception must move it out of the
/// open filter without a second round trip to discover that.
class ExceptionController extends ChangeNotifier {
  ExceptionController({required ExceptionRepository repository})
      : _repository = repository;

  final ExceptionRepository _repository;

  List<ReviewExceptionSummary> _items = const <ReviewExceptionSummary>[];
  final Map<int, ReviewExceptionDetail> _details =
      <int, ReviewExceptionDetail>{};
  final Set<int> _loadingDetails = <int>{};
  ExceptionFilter _filter = ExceptionFilter.all;
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _isReviewing = false;
  String? _errorMessage;
  String? _detailError;

  List<ReviewExceptionSummary> get items => _items;
  ExceptionFilter get filter => _filter;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get isReviewing => _isReviewing;
  String? get errorMessage => _errorMessage;

  /// How many entries are still waiting, across the whole roster.
  int get openCount =>
      _items.where((ReviewExceptionSummary item) => item.isOpen).length;

  ReviewExceptionDetail? detailFor(int exceptionId) => _details[exceptionId];

  bool isLoadingDetail(int exceptionId) =>
      _loadingDetails.contains(exceptionId);

  /// Error from the most recent detail request, if it failed.
  String? get detailError => _detailError;

  /// Loads the queue. A failure keeps the previous rows visible with the error
  /// surfaced, so a refresh never blanks the page a clinician is reading.
  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _items = await _repository.list(filter: _filter);
      _hasLoaded = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switches which slice of the queue is shown, refetching for the new status.
  Future<void> applyFilter(ExceptionFilter filter) async {
    if (filter == _filter) {
      return;
    }
    _filter = filter;
    await load();
  }

  /// Fetches the evidence behind one entry, once.
  Future<void> loadDetail(int exceptionId) async {
    if (_details.containsKey(exceptionId) ||
        _loadingDetails.contains(exceptionId)) {
      return;
    }
    _loadingDetails.add(exceptionId);
    _detailError = null;
    notifyListeners();
    try {
      _details[exceptionId] = await _repository.detail(exceptionId);
    } on ApiException catch (error) {
      _detailError = error.message;
    } finally {
      _loadingDetails.remove(exceptionId);
      notifyListeners();
    }
  }

  /// Records the doctor's decision. Returns true when the server accepted it.
  ///
  /// The refreshed row is written into both the detail cache and the queue, so
  /// the entry the clinician just closed never lingers in the open list.
  Future<bool> review({
    required int exceptionId,
    required ReviewOutcome outcome,
    String? note,
  }) async {
    _isReviewing = true;
    _detailError = null;
    notifyListeners();
    try {
      final ReviewExceptionDetail updated = await _repository.review(
        exceptionId: exceptionId,
        outcome: outcome,
        note: note,
      );
      _details[exceptionId] = updated;
      _items = _items
          .map(
            (ReviewExceptionSummary item) =>
                item.id == exceptionId ? updated.summary : item,
          )
          .toList(growable: false);
      return true;
    } on ApiException catch (error) {
      _detailError = error.message;
      return false;
    } finally {
      _isReviewing = false;
      notifyListeners();
    }
  }
}
