import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../check_ins/presentation/check_in_screen.dart';
import '../../doctor_links/presentation/doctors_screen.dart';
import '../../home/presentation/home_screen.dart';

/// The signed-in shell: a bottom navigation bar over the app's three modules.
///
/// Each module owns its tab, so home, check-ins and doctor linking stay
/// decoupled and can each grow without crowding the others. An [IndexedStack]
/// keeps every tab's state (scroll position, loaded data) while switching.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    HomeScreen(),
    CheckInsScreen(),
    DoctorsScreen(),
  ];

  void _select(int index) {
    if (index == _index) {
      return;
    }
    setState(() => _index = index);
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
