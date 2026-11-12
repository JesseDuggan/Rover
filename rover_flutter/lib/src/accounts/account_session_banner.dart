import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'account_library.dart';

/// Checks credentials when the app opens or resumes, without interrupting a walk.
class AccountSessionBanner extends StatefulWidget {
  const AccountSessionBanner({super.key, this.library});
  final AccountLibrary? library;

  @override
  State<AccountSessionBanner> createState() => _AccountSessionBannerState();
}

class _AccountSessionBannerState extends State<AccountSessionBanner>
    with WidgetsBindingObserver {
  late final library = widget.library ?? AccountLibrary.instance;
  bool checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    try {
      await library.load();
      await library.checkSession();
    } catch (_) {
      // Temporary connectivity failures must not sign someone out.
      // Account screens retain their retry actions.
    } finally {
      checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => library.sessionNotice == null
        ? const SizedBox.shrink()
        : MaterialBanner(
            content: Text(library.sessionNotice!),
            leading: const Icon(Icons.account_circle_outlined),
            actions: [
              TextButton(
                onPressed: () => context.push('/profile/account'),
                child: const Text('Sign in again'),
              ),
            ],
          ),
  );
}
