import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/email_check_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/auth/presentation/screens/email_verification_screen.dart';
import '../features/chat/data/repositories/chat_repository.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/chat/presentation/screens/chat_screen.dart';
import '../features/warranty/data/repositories/warranty_repository.dart';
import '../features/warranty/presentation/providers/warranty_provider.dart';
import '../features/warranty/presentation/screens/warranty_screen.dart';
import '../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../features/warranty/presentation/screens/check_warranty_screen.dart';
import '../features/feedback/presentation/screens/feedback_screen.dart';
import '../features/sort/data/repositories/sort_repository.dart';
import '../features/sort/presentation/providers/sort_provider.dart';
import '../features/sort/presentation/screens/sort_screen.dart';
import 'theme/app_theme.dart';
import 'navigation/main_navigation_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            AuthRepository(ApiClient()),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ChatProvider(
            ChatRepository(ApiClient()),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => WarrantyProvider(
            WarrantyRepository(ApiClient()),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SortProvider(
            SortRepository(ApiClient()),
          ),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          // Show loading screen while checking saved session
          if (!authProvider.isInitialized) {
            return const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          return MaterialApp(
            title: 'PhongVu OpsHub',
            theme: AppTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            home: authProvider.isAuthenticated
                ? const MainNavigationScreen()
                : const EmailCheckScreen(),
            routes: {
              '/login': (context) => const EmailCheckScreen(),
              '/register': (context) => const RegisterScreen(email: ''),
              '/email-verification': (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
                return EmailVerificationScreen(
                  name: args?['name'] ?? '',
                  email: args?['email'] ?? '',
                  password: args?['password'] ?? '',
                );
              },
              '/home': (context) => const MainNavigationScreen(),
              '/chat': (context) => const ChatScreen(),
              '/warranty-main': (context) => const WarrantyMainScreen(),
              '/warranty': (context) => const WarrantyScreen(),
              '/check-warranty': (context) => const CheckWarrantyScreen(),
              '/feedback': (context) => const FeedbackScreen(),
              '/sort': (context) => const SortScreen(),
            },
          );
        },
      ),
    );
  }
}
