import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'main_page.dart';
import 'onboarding_page.dart';
import 'sign_in_page.dart';
import 'splash_page.dart';

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    if (!session.bootstrapped) {
      return const SplashPage();
    }

    if (!session.onboardingDone) {
      return const OnboardingPage();
    }

    if (!session.isLoggedIn) {
      return const SignInPage();
    }

    return const MainPage();
  }
}
