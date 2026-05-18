import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFAFFFF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: const AssetImage('assets/images/image-logo.png'),
              width: 120,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/images/logo.png',
                width: 120,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 120,
                  height: 120,
                  child: Center(
                    child: Icon(Icons.restaurant, size: 56, color: Color(0xFF27B48A)),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'SMART SNACK',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF27B48A)),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Color(0xFF27B48A)),
          ],
        ),
      ),
    );
  }
}
