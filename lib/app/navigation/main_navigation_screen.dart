import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/fifo/presentation/screens/fifo_check_screen.dart';
import '../../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 1, // Default to Home
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  DateTime? _lastBackPress;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  List<Widget> _screens(bool canUseCp62Flows) {
    if (!canUseCp62Flows) {
      return const [HomeScreen(key: ValueKey('screen_home'))];
    }
    return [
      FifoCheckScreen(
        key: const ValueKey('screen_fifo'),
        onBackToHome: () => _backToHome(canUseCp62Flows),
      ),
      const HomeScreen(key: ValueKey('screen_home')),
      WarrantyMainScreen(
        key: const ValueKey('screen_warranty'),
        onBackToHome: () => _backToHome(canUseCp62Flows),
      ),
    ];
  }

  List<NavigationDestination> _destinations(bool canUseCp62Flows) {
    if (!canUseCp62Flows) {
      return const [
        NavigationDestination(
          key: ValueKey('nav_home'),
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
          tooltip: 'Trang chủ',
        ),
      ];
    }
    return const [
      NavigationDestination(
        key: ValueKey('nav_fifo'),
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: 'FIFO',
        tooltip: 'Tra cứu & sắp xếp FIFO',
      ),
      NavigationDestination(
        key: ValueKey('nav_home'),
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Home',
        tooltip: 'Trang chủ',
      ),
      NavigationDestination(
        key: ValueKey('nav_warranty'),
        icon: Icon(Icons.headset_mic_outlined),
        selectedIcon: Icon(Icons.headset_mic),
        label: 'Bảo hành',
        tooltip: 'Bảo hành & Sửa chữa',
      ),
    ];
  }

  int _homeIndex(bool canUseCp62Flows) => canUseCp62Flows ? 1 : 0;

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Refresh user data when Home button is tapped (throttled: max once per 5 min)
    final canUseCp62Flows =
        context.read<AuthProvider>().user?.canUseCp62RestrictedFlows == true;
    if (index == _homeIndex(canUseCp62Flows)) {
      final now = DateTime.now();
      if (_lastRefresh == null ||
          now.difference(_lastRefresh!) > const Duration(minutes: 5)) {
        _lastRefresh = now;
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.refreshUserData();
      }
    }
  }

  void _backToHome(bool canUseCp62Flows) {
    _onItemTapped(_homeIndex(canUseCp62Flows));
  }

  Future<bool> _handleBackNavigation(bool canUseCp62Flows) async {
    // If not on home screen, go back to home
    if (_currentIndex != _homeIndex(canUseCp62Flows)) {
      _backToHome(canUseCp62Flows);
      return false; // Don't exit app
    }

    // On home screen, check double back to exit
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      return true; // Allow exit
    }

    // First back press on home
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhấn back lần nữa để thoát'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false; // Don't exit
  }

  @override
  Widget build(BuildContext context) {
    final canUseCp62Flows = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseCp62RestrictedFlows == true,
    );
    final screens = _screens(canUseCp62Flows);
    final destinations = _destinations(canUseCp62Flows);
    final selectedIndex = _currentIndex.clamp(0, screens.length - 1).toInt();
    if (selectedIndex != _currentIndex) {
      _currentIndex = selectedIndex;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _handleBackNavigation(canUseCp62Flows);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: selectedIndex, children: screens),
        bottomNavigationBar: destinations.length < 2
            ? null
            : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: _onItemTapped,
                destinations: destinations,
              ),
      ),
    );
  }
}
