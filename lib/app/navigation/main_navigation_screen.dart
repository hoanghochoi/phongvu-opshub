import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../theme/app_theme.dart';

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

    // Refresh user data when Home button is tapped
    if (index == 1) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.refreshUserData();
    }
  }

  void _backToHome() {
    // Refresh user data
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.refreshUserData();
    // Navigate to home
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
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Chat button (left)
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
                            color: _currentIndex == 0 ? AppTheme.primaryBlue : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Chat',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 0 ? AppTheme.primaryBlue : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Home button (center) with 3D effect
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentIndex == 1 ? AppTheme.primaryBlue : Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.home,
                              size: 22,
                              color: _currentIndex == 1 ? Colors.white : AppTheme.iconColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 1 ? AppTheme.primaryBlue : Colors.grey,
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
                            _currentIndex == 2 ? Icons.build_circle : Icons.build_circle_outlined,
                            color: _currentIndex == 2 ? AppTheme.primaryBlue : Colors.grey,
                            size: 24,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Bảo hành',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _currentIndex == 2 ? FontWeight.bold : FontWeight.normal,
                              color: _currentIndex == 2 ? AppTheme.primaryBlue : Colors.grey,
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
    );
  }

  // Provide a method to change tab from outside
  static void changeTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainNavigationScreenState>();
    state?._onItemTapped(index);
  }
}
