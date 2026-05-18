import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cek_sugar_page.dart';
import 'health_monitoring_page.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'article_page.dart';
import 'tambah_kemasan_page.dart';
import '../providers/app_providers.dart';

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      const TambahKemasanPage(),
      const CekSugarPage(),
      const HealthMonitoringPage(),
      ArticlePage(
        onBackHome: () => setState(() => _index = 0),
      ),
      const ProfilePage(),
    ];
    // ─── OLD middleItemIcon / middleItemLabel ───
    // const middleItemIcon = Icons.add_box_outlined;
    // const middleItemLabel = 'Tambah Kemasan';

    // ─── OLD Scaffold ───────────────────────────────────────────────────
    // return Scaffold(
    //   body: IndexedStack(index: _index, children: pages),
    //   bottomNavigationBar: BottomNavigationBar(
    //     type: BottomNavigationBarType.fixed,
    //     currentIndex: _index,
    //     selectedItemColor: const Color(0xFF27B48A),
    //     unselectedItemColor: const Color(0xFF6B7280),
    //     showUnselectedLabels: true,
    //     onTap: (value) {
    //       if (value == 5) {
    //         ref.read(profileRefreshSignalProvider.notifier).state++;
    //       }
    //       setState(() => _index = value);
    //     },
    //     items: [
    //       const BottomNavigationBarItem(
    //           icon: Icon(Icons.home_outlined), label: 'Home'),
    //       BottomNavigationBarItem(
    //           icon: Icon(middleItemIcon), label: middleItemLabel),
    //       const BottomNavigationBarItem(
    //           icon: Icon(Icons.document_scanner_outlined), label: 'Cek Sugar'),
    //       const BottomNavigationBarItem(
    //           icon: Icon(Icons.monitor_heart_outlined), label: 'Cek Diabetes'),
    //       const BottomNavigationBarItem(
    //           icon: Icon(Icons.article_outlined), label: 'Artikel'),
    //       const BottomNavigationBarItem(
    //           icon: Icon(Icons.emoji_emotions_outlined), label: 'User Profile'),
    //     ],
    //   ),
    // );
    // ─── NEW PREMIUM Scaffold ─────────────────────────────────────────────
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey<int>(_index),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFF0F0F0), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: BottomNavigationBar(
              currentIndex: _index,
              elevation: 0,
              backgroundColor: Colors.transparent,
              onTap: (value) {
                if (value == 5) {
                  ref.read(profileRefreshSignalProvider.notifier).state++;
                }
                setState(() => _index = value);
              },
              items: [
                _navItem(Icons.home_rounded, Icons.home_outlined, 'Home', 0),
                _navItem(Icons.add_circle_rounded, Icons.add_circle_outline, 'Tambah', 1),
                _navItem(Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_rounded, 'Cek Sugar', 2),
                _navItem(Icons.monitor_heart_rounded, Icons.monitor_heart_outlined, 'Kesehatan', 3),
                _navItem(Icons.auto_stories_rounded, Icons.auto_stories_outlined, 'Artikel', 4),
                _navItem(Icons.person_rounded, Icons.person_outline_rounded, 'Profil', 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _navItem(
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
    int index,
  ) {
    final isSelected = _index == index;
    return BottomNavigationBarItem(
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D9F6E).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isSelected ? activeIcon : inactiveIcon,
          size: 24,
        ),
      ),
      label: label,
    );
  }
}
