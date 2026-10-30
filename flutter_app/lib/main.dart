import 'dart:async';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'ui/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(_LifecycleHost(controller: controller));
}

class _LifecycleHost extends StatefulWidget {
  const _LifecycleHost({required this.controller});
  final AppController controller;
  @override
  State<_LifecycleHost> createState() => _LifecycleHostState();
}

class _LifecycleHostState extends State<_LifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ([
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ].contains(state)) {
      widget.controller.pauseTranslation();
      unawaited(widget.controller.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LangPackStartup(controller: widget.controller);
}
