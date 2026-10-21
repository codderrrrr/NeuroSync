import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import '../../../app_scope.dart';
import '../../../core/widgets/floating_tab_bar.dart';
import '../../account/presentation/account_screen.dart';
import '../../doctor_links/presentation/doctors_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../medication/presentation/medications_screen.dart';
import '../../medication/state/medication_controller.dart';
import '../../tests/presentation/tests_screen.dart';

/// The signed-in shell: five destinations over the patient's own information.
///
/// The destinations are the questions a patient actually has when they open
/// the app: how am I doing, what am I taking, what did my tests show, who is
/// looking after me, and where do I sign out. Each one is a tab, so the
/// patient's place in each is kept while they move between them.
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

  /// The medication list is a tab, so its controller is held here rather than
  /// looked up on every build.
  MedicationController? _medications;

  int _index = 0;
  Timer? _pollTimer;
  bool _isRefreshing = false;

  static const List<TabDestination> _destinations = <TabDestination>[
    TabDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
    ),
    TabDestination(
      icon: Icons.medication_outlined,
      selectedIcon: Icons.medication_rounded,
      label: 'Medicine',
    ),
    TabDestination(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
      label: 'Tests',
    ),
    TabDestination(
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
      label: 'Doctors',
    ),
    TabDestination(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Account',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The medication list is a tab, so its controller is held here rather than
    // looked up on every build. It cannot be looked up in initState: an
    // inherited widget is not available until the dependencies are read.
    _medications ??= AppScope.of(context).medications;
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
    final AppColors colors = AppColors.of(context);
    final List<Widget> tabs = <Widget>[
      const HomeScreen(),
      MedicationsScreen(
          controller: _medications ?? AppScope.of(context).medications),
      const TestsScreen(),
      const DoctorsScreen(),
      const AccountScreen(),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      // The bar floats, so the page needs room to scroll under it.
      extendBody: true,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: FloatingTabBar(
        destinations: _destinations,
        selectedIndex: _index,
        onSelected: _select,
      ),
    );
  }
}
