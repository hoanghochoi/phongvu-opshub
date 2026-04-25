import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
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

  // Static constants to avoid recreating per build
  static const _activeGradient = LinearGradient(
    colors: [Color(0xFF0D1B6F), Color(0xFF3B5FCC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static final _homeShadow = [
    BoxShadow(
      color: const Color(0xFF0D1B6F).withValues(alpha: 0.3),
      blurRadius: 8,
      spreadRadius: 1,
      offset: const Offset(0, 2),
    ),
  ];
  static final _navBarShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, -4),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _screens = [
      ChatScreen(key: const ValueKey('screen_chat'), onBackToHome: _backToHome),
      HomeScreen(key: const ValueKey('screen_home'), onTabChange: _onItemTapped),
      WarrantyMainScreen(key: const ValueKey('screen_warranty'), onBackToHome: _backToHome),
    ];
  }

  late final List<Widget> _screens;

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Refresh user data when Home button is tapped (throttled: max once per 5 min)
    if (index == 1) {
      final now = DateTime.now();
      if (_lastRefresh == null || now.difference(_lastRefresh!) > const Duration(minutes: 5)) {
        _lastRefresh = now;
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.refreshUserData();
      }
    }
  }

  void _backToHome() {
    _onItemTapped(1);
  }

  Future<bool> _handleBackNavigation() async {
    // If not on home screen, go back to home
    if (_currentIndex != 1) {
      _backToHome();
      return false; // Don't exit app
    }

    // On home screen, check double back to exit
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _handleBackNavigation();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: _navBarShadow,
            ),
          child: SafeArea(
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // FIFO button (left)
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('nav_chat'),
                      onTap: () => _onItemTapped(0),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentIndex == 0 ? Icons.chat_bubble : Icons.chat_bubble_outline,
                            color: _currentIndex == 0 ? const Color(0xFF0D1B6F) : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Chat',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 0 ? const Color(0xFF0D1B6F) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Home button (center)
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('nav_home'),
                      onTap: () => _onItemTapped(1),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _currentIndex == 1
                                  ? _activeGradient
                                  : null,
                              color: _currentIndex == 1 ? null : Colors.white,
                              boxShadow: _homeShadow,
                            ),
                            child: Icon(
                              Icons.home_rounded,
                              size: 22,
                              color: _currentIndex == 1 ? Colors.white : const Color(0xFF0D1B6F),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 1 ? const Color(0xFF0D1B6F) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Warranty button (right)
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('nav_warranty'),
                      onTap: () => _onItemTapped(2),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentIndex == 2 ? Icons.headset_mic : Icons.headset_mic_outlined,
                            color: _currentIndex == 2 ? const Color(0xFF0D1B6F) : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bảo hành',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _currentIndex == 2 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 2 ? const Color(0xFF0D1B6F) : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}
