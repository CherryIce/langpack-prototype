import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A settings detail route whose content follows controller updates.
class SettingsDetailPage extends StatelessWidget {
  const SettingsDetailPage({
    super.key,
    required this.title,
    required this.listenable,
    required this.builder,
    required this.english,
  });

  final String title;
  final Listenable listenable;
  final WidgetBuilder builder;
  final bool english;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8F4),
    resizeToAvoidBottomInset: true,
    appBar: CupertinoNavigationBar(
      backgroundColor: Colors.white,
      border: const Border(
        bottom: BorderSide(color: Color(0xFFE1E9E2), width: 0.5),
      ),
      previousPageTitle: english ? 'Settings' : '设置',
      middle: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: PageStorageKey(title),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: listenable,
                builder: (context, _) => builder(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
