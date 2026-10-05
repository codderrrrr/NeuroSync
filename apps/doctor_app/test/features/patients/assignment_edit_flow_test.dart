import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neurosync_doctor/features/patients/models/assignment.dart';
import 'package:neurosync_doctor/features/patients/presentation/assignment_page.dart';
import 'package:neurosync_doctor/features/roster/presentation/patient_detail_page.dart';

import '../../test_support.dart';

/// The exercise the doctor opens, already assigned with settings that differ
/// from the catalog defaults, so a page showing defaults instead of what was
/// stored is caught rather than passed off as correct.
final Map<String, dynamic> _storedJson = assignmentJson(
  id: 77,
  title: 'Morning tracing',
  durationSeconds: 90,
  assessmentSlug: 'line_tracing',
  assessmentTitle: 'Line Tracing',
  parameters: <String, Object>{
    'pacing': 'fast',
    'repetitions': 5,
    'line_length_percent': 55,
  },
);

/// An exercise assigned while its test was still being handed out.
///
/// `spiral_drawing` is held back today, which is exactly the state a real
/// database can be in, and the state the editor has to handle.
final Map<String, dynamic> _heldBackJson = assignmentJson(
  id: 78,
  title: 'Morning spiral',
  durationSeconds: 90,
  assessmentSlug: 'spiral_drawing',
  assessmentTitle: 'Spiral Drawing',
  parameters: <String, Object>{
    'pacing': 'fast',
    'turns': 5,
    'size_percent': 55,
  },
);

/// One request the page made, decoded so the assertions read as data.
class _Call {
  _Call(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> body;

  @override
  String toString() => '$method $path ${jsonEncode(body)}';
}

/// Answers the catalog, the assignment list and the write the edit page makes,
/// recording every write so the test can assert what the doctor actually sent.
class _Api {
  _Api({Map<String, dynamic>? stored}) : stored = stored ?? _storedJson;

  final Map<String, dynamic> stored;
  final List<_Call> writes = <_Call>[];

  Future<http.Response> call(http.Request request) async {
    final String path = request.url.path;
    if (path == '/doctor/assessments') {
      return json(assessmentCatalogJson());
    }
    if (path.endsWith('/assignments')) {
      return json(<dynamic>[stored]);
    }
    final _Call call = _Call(
      request.method,
      path,
      request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>,
    );
    writes.add(call);
    return json(<String, dynamic>{
      ...stored,
      ...call.body,
      'parameters': call.body['parameters'] ?? stored['parameters'],
    });
  }
}

Future<_Api> _pumpEditor(
  WidgetTester tester, {
  Size viewport = const Size(1280, 900),
  Map<String, dynamic>? editing,
}) async {
  final Map<String, dynamic> stored = editing ?? _storedJson;
  final _Api api = _Api(stored: stored);
  await pumpDoctorScreen(
    tester,
    home: AssignmentPage(
      patientId: 41,
      patientName: 'Maya Lindqvist',
      existing: Assignment.fromJson(stored),
    ),
    handler: api.call,
    viewport: viewport,
  );
  await tester.pumpAndSettle();
  return api;
}

/// Scrolls the page until [finder] is on screen, because the editor grows past
/// the fold and the submit row sits at the very bottom.
///
/// The first scrollable is the page's own list; the ones after it belong to
/// text fields, which scroll horizontally and would never reveal anything.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(Scrollable).first,
    const Offset(0, -140),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the editor opens on the settings the assignment was given', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(tester);

    expect(tester.takeException(), isNull);
    // The stored test, not a fresh assignment page.
    expect(find.text('Edit exercise'), findsOneWidget);

    await _scrollTo(tester, find.text('HOW THE PATIENT DOES IT'));
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Repetitions'), findsOneWidget);
    expect(find.text('Line length'), findsOneWidget);
    // Repetitions was set to 5, not left at the catalog default of 3.
    expect(find.text('5'), findsOneWidget);

    await _scrollTo(tester, find.text('Save changes'));
    // The title box opens on the stored title. An empty one would be submitted
    // as an empty title, erasing the name the doctor gave this exercise.
    expect(find.text('Morning tracing'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('changing one setting sends the whole replacement set', (
    WidgetTester tester,
  ) async {
    final _Api api = await _pumpEditor(tester);

    await _scrollTo(tester, find.text('HOW THE PATIENT DOES IT'));
    // Speed goes from the stored `fast` to `slow`.
    await tester.tap(find.text('Slow'));
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(api.writes, hasLength(1));
    final _Call write = api.writes.single;
    expect(write.method, 'PATCH');
    expect(write.path, '/doctor/patients/41/assignments/77');
    // Every setting is sent, not just the one that changed: the API replaces
    // the stored set outright, so sending only `pacing` would reset the rest.
    expect(write.body['parameters'], <String, Object>{
      'pacing': 'slow',
      'repetitions': 5,
      'line_length_percent': 55,
    });
    expect(write.body['duration_seconds'], 90);
    expect(write.body['title'], 'Morning tracing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving without touching anything still sends that exercise', (
    WidgetTester tester,
  ) async {
    // The editor is seeded from the stored values, so an untouched save must
    // not blank the settings the patient was last given.
    final _Api api = await _pumpEditor(tester);

    await _scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(api.writes, hasLength(1));
    expect(api.writes.single.body['parameters'], <String, Object>{
      'pacing': 'fast',
      'repetitions': 5,
      'line_length_percent': 55,
    });
    // And the title survives a save that never touched it.
    expect(api.writes.single.body['title'], 'Morning tracing');
  });

  testWidgets('a rejected setting is reported and not treated as saved', (
    WidgetTester tester,
  ) async {
    // The API is the authority on bounds; the page must surface its refusal
    // rather than closing as though the edit landed.
    Future<http.Response> handler(http.Request request) async {
      if (request.method == 'PATCH') {
        return json(<String, dynamic>{
          'detail': "Repetitions must be between 1 and 10.",
        }, 422);
      }
      final _Api api = _Api();
      return api.call(request);
    }

    await pumpDoctorScreen(
      tester,
      home: AssignmentPage(
        patientId: 41,
        patientName: 'Maya Lindqvist',
        existing: Assignment.fromJson(_storedJson),
      ),
      handler: handler,
      viewport: const Size(1280, 900),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Repetitions must be between 1 and 10.'),
        findsOneWidget);
    // Still open, still editable: the doctor sees the error where they made
    // the change instead of being dropped back on the roster.
    await _scrollTo(tester, find.text('Save changes'));
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('the edit editor fits a narrow window', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(tester, viewport: const Size(480, 900));

    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.text('HOW THE PATIENT DOES IT'));
    expect(find.text('Repetitions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit on the patient page opens an editor that can be saved', (
    WidgetTester tester,
  ) async {
    // The real entry point. The test cannot be re-picked once editing, so
    // nothing else forces the page to rebuild when the catalogue arrives; an
    // editor that only ever reads it at first build would open with no
    // settings at all and an unsaveable form.
    final _Api api = _Api();
    await pumpDoctorScreen(
      tester,
      home: const PatientDetailPage(
        patientId: 41,
        patientName: 'Maya Lindqvist',
      ),
      handler: api.call,
      viewport: const Size(1280, 900),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('Edit exercise'), findsOneWidget);
    await _scrollTo(tester, find.text('HOW THE PATIENT DOES IT'));
    expect(find.text('Speed'), findsOneWidget);
    // Stored values, not catalog defaults.
    expect(find.text('5'), findsOneWidget);

    await _scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(api.writes, hasLength(1));
    expect(api.writes.single.method, 'PATCH');
    expect(api.writes.single.path, '/doctor/patients/41/assignments/77');
  });

  testWidgets('a held-back exercise cannot be saved, and says why', (
    WidgetTester tester,
  ) async {
    // The API refuses this edit: the patient's plan stopped offering the
    // exercise when the test was held back, so saving would change nothing
    // anyone ever sees. The page has to agree instead of offering a button
    // that can only come back as an error.
    final _Api api = await _pumpEditor(tester, editing: _heldBackJson);

    expect(tester.takeException(), isNull);
    // The test itself is labelled too, so the reason is on screen twice: once
    // on the card, once on the note that explains what the doctor can do.
    // Checked before scrolling: the list builds what fits around the viewport,
    // so a card left far above the fold is gone by the time the note is read.
    expect(find.text('COMING SOON'), findsNWidgets(2));

    await _scrollTo(tester, find.textContaining('Remove it from the patient'));
    expect(find.textContaining('Remove it from the patient'), findsOneWidget);

    // Tapping the disabled button sends nothing at all.
    await _scrollTo(tester, find.text('Save changes'));
    await tester.tap(find.text('Save changes'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(api.writes, isEmpty);
  });
}
