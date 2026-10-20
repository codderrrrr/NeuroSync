import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../check_ins/presentation/check_in_screen.dart';
import '../../doctor_links/presentation/doctors_screen.dart';
import '../../home/presentation/home_screen.dart';

/// The signed-in shell: a bottom navigation bar over the app's three modules.
///
/// Each module owns its tab, so home, check-ins and doctor linking stay
/// decoupled and can each grow without crowding the others. An [IndexedStack]
/// keeps every tab's state (scroll position, loaded data) while switching.
///
/// The shell is also what keeps those tabs current. A doctor assigns an
/// exercise, or accepts a link request, on their own machine; nothing pushes
/// that to the patient, so without a refresh the patient only finds out by
/// killing and reopening the app. The shell refreshes on a timer, whenever the
/// app comes back to the foreground, and whenever the patient switches tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  /// How often to re-read while the patient is looking at the app.
  ///
  /// Both reads are small and the controllers only show a spinner before their
  /// first successful load, so a refresh that changes nothing is invisible.
  static const Duration _pollInterval = Duration(seconds: 20);

  int _index = 0;
  Timer? _pollTimer;
  bool _isRefreshing = false;

  static const List<Widget> _tabs = <Widget>[
    HomeScreen(),
    CheckInsScreen(),
    DoctorsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground is exactly when a change made on the other
    // side is most likely to be waiting, and the timer may not have fired.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _select(int index) {
    if (index == _index) {
      return;
    }
    setState(() => _index = index);
    // Switching tabs is the patient asking to see something, so answer with
    // current data rather than whatever was loaded when the shell was built.
    _refresh();
  }

  /// Re-read what a doctor may have changed while the app was open.
  ///
  /// A failed refresh is deliberately silent: the controllers keep the last
  /// good data and expose their own error state, and an intermittent network
  /// blip must not replace a plan the patient can still do with an error.
  Future<void> _refresh() async {
    if (_isRefreshing || !mounted) {
      return;
    }
    _isRefreshing = true;
    try {
      final AppScope scope = AppScope.of(context);
      await Future.wait<void>(<Future<void>>[
        scope.monitoring.loadPlan(),
        scope.doctorLinks.load(),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        backgroundColor: AppTheme.darkSurface,
        surfaceTintColor: Colors.transparent,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Check-ins',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Doctors',
          ),
        ],
      ),
    );
  }
}
