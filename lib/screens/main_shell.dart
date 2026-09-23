import 'package:flutter/material.dart';

import '../ads/ad_helper.dart';
import '../services/auth_service.dart';
import '../widgets/ads/cafein_banner_ad.dart';
import 'auth_required_screen.dart';
import 'home_screen.dart';
import 'my_info_screen.dart';
import 'write_post_screen.dart';

/// Bottom navigation: Home / Write / MyInfo
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// 0: home, 1: my info (write is action)
  int _tab = 0;
  final _authService = AuthService.instance;

  int get _navIndex => _tab == 0 ? 0 : 2;

  Future<void> _openWrite() async {
    if (!_authService.hasCompletedOnboarding) {
      final ready = await AuthRequiredScreen.ensureWriter(context);
      if (!ready || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WritePostScreen()),
    );
  }

  void _onDestinationSelected(int index) {
    if (index == 1) {
      _openWrite();
      return;
    }
    setState(() => _tab = index == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(isActive: _tab == 0),
          const MyInfoScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AdHelper.showBottomBannerAd) const CafeinBannerAd(),
          const Divider(height: 0.5, thickness: 0.5),
          NavigationBar(
            selectedIndex: _navIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '홈',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_outlined),
                selectedIcon: Icon(Icons.edit),
                label: '글쓰기',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '내정보',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
