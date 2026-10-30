import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controller.dart';
import 'app.dart';
import 'onboarding.dart';

/// Keeps the introduction preference separate from project and credential data.
class LangPackStartup extends StatefulWidget {
  const LangPackStartup({super.key, required this.controller});
  static const introductionKey = 'langpack_introduction_v1';
  final AppController controller;

  @override
  State<LangPackStartup> createState() => _LangPackStartupState();
}

class _LangPackStartupState extends State<LangPackStartup> {
  SharedPreferences? _preferences;
  bool _ready = false;
  bool _showIntroduction = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    var newUser = false;
    try {
      _preferences = await SharedPreferences.getInstance();
      final introduction = _preferences!.getBool(
        LangPackStartup.introductionKey,
      );
      newUser =
          introduction == false ||
          (introduction != true &&
              !_preferences!.containsKey(AppController.storageKey));
      if (newUser && introduction == null) {
        await _preferences!.setBool(LangPackStartup.introductionKey, false);
      }
    } catch (_) {
      // A preference read failure must not hide an existing workspace.
    }
    await widget.controller.initialize();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _showIntroduction = newUser;
    });
  }

  Future<void> _finishIntroduction() async {
    // Enter immediately; saving this preference never blocks the workspace.
    setState(() => _showIntroduction = false);
    try {
      await _preferences?.setBool(LangPackStartup.introductionKey, true);
    } catch (_) {
      // Project persistence has its own error reporting in AppController.
    }
  }

  @override
  Widget build(BuildContext context) => LangPackApp(
    controller: widget.controller,
    startup: !_ready
        ? const LangPackSplash()
        : _showIntroduction
        ? LangPackOnboarding(
            english: widget.controller.settings.interfaceLocale == 'en',
            onLocaleChanged: (english) =>
                widget.controller.setInterfaceLocale(english ? 'en' : 'zh'),
            onComplete: _finishIntroduction,
          )
        : null,
  );
}
