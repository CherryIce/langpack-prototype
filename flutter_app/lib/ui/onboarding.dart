import 'dart:math' as math;

import 'package:flutter/material.dart';

const brandGreen = Color(0xFF197E64);
const brandInk = Color(0xFF243E34);
const brandCanvas = Color(0xFFF5F8F4);
const _mint = Color(0xFFCDE9D9);
const _muted = Color(0xFF5E7669);

class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .24),
    child: Image.asset(
      'assets/brand/app-icon.png',
      width: size,
      height: size,
      excludeFromSemantics: true,
    ),
  );
}

/// This frame lasts only while local preferences and projects are being read.
class LangPackSplash extends StatelessWidget {
  const LangPackSplash({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: brandCanvas,
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandIcon(size: 96),
            SizedBox(height: 24),
            Text(
              'LangPack',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.1,
                color: brandInk,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'WORDS WITHOUT BORDERS',
              style: TextStyle(fontSize: 10, letterSpacing: 2, color: _muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class LangPackOnboarding extends StatefulWidget {
  const LangPackOnboarding({
    super.key,
    required this.onComplete,
    this.english = false,
    this.onLocaleChanged,
  });
  final VoidCallback onComplete;
  final bool english;
  final ValueChanged<bool>? onLocaleChanged;

  @override
  State<LangPackOnboarding> createState() => _LangPackOnboardingState();
}

class _LangPackOnboardingState extends State<LangPackOnboarding> {
  int _page = 0;
  late bool _english = widget.english;
  String _t(String zh, String en) => _english ? en : zh;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final titles = [
      _t('把文案，\n轻轻装进来', 'A little text.\nA world of possibility.'),
      _t('一种表达，\n走向多种语言', 'Your words.\nMore languages.'),
      _t('认真校对，\n安心交付', 'Review with care.\nDeliver with confidence.'),
    ];
    final descriptions = [
      _t(
        '输入文字，或导入 TXT、Markdown、DOCX。把每一句原文，整理成清晰的语言条目。',
        'Type your text or import TXT, Markdown and DOCX. Give every source string a clear place to start.',
      ),
      _t(
        '在 35 种语言中选择目标，按需配置翻译平台。让新增文案与缺失译文，接着完成。',
        'Choose targets from 35 languages and configure your providers. Keep going with new strings and missing translations.',
      ),
      _t(
        '逐条检查译文与占位符，再导出 JSON 或 ZIP。让每一个语言包，都有条不紊。',
        'Check translations and placeholders, then export JSON or ZIP. Every language pack, ready for its next step.',
      ),
    ];

    return Scaffold(
      backgroundColor: brandCanvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 800;
            final padding = wide ? 48.0 : 24.0;
            final illustration = Semantics(
              label: _t(
                '功能示意，第 ${_page + 1} 步',
                'Feature illustration, step ${_page + 1}',
              ),
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  child: SizedBox(
                    key: ValueKey('illustration-$_page'),
                    width: 360,
                    height: 320,
                    child: OnboardingIllustration(
                      page: _page,
                      english: _english,
                    ),
                  ),
                ),
              ),
            );
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [
                    'COLLECT YOUR WORDS',
                    'MAKE IT MULTILINGUAL',
                    'READY TO SHIP',
                  ][_page],
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w600,
                    color: brandGreen,
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  titles[_page],
                  key: const ValueKey('onboarding-title'),
                  style: TextStyle(
                    fontSize: wide ? 38 : 30,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.9,
                    color: brandInk,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  descriptions[_page],
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.85,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final label in [
                      ['TXT', 'Markdown', 'DOCX'],
                      [_t('35 种语言', '35 languages'), _t('增量翻译', 'Incremental')],
                      ['JSON', 'ZIP', _t('占位符检查', 'Placeholder checks')],
                    ][_page])
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE1E9E2)),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(fontSize: 10, color: _muted),
                        ),
                      ),
                  ],
                ),
              ],
            );
            final controls = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Semantics(
                        selected: i == _page,
                        label: _t('第 ${i + 1} 页，共 3 页', 'Page ${i + 1} of 3'),
                        child: IconButton(
                          key: ValueKey('onboarding-dot-$i'),
                          onPressed: () => setState(() => _page = i),
                          icon: AnimatedContainer(
                            duration: reducedMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            width: i == _page ? 24 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? brandGreen
                                  : const Color(0xFFD2DFD5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '0${_page + 1} / 03',
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              color: _muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('onboarding-next'),
                    onPressed: _page == 2
                        ? widget.onComplete
                        : () => setState(() => _page++),
                    style: FilledButton.styleFrom(
                      backgroundColor: brandGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _page == 2
                                ? _t('开启我的工作台', 'Open my workspace')
                                : _t('下一步', 'Continue'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: _page > 0
                      ? TextButton(
                          key: const ValueKey('onboarding-back'),
                          onPressed: () => setState(() => _page--),
                          child: Text(
                            _t('上一步', 'Back'),
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        )
                      : Center(
                          child: Text(
                            _t('从一句话，开始连接世界', 'Small words. Wider worlds.'),
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ),
                ),
              ],
            );

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padding, 16, padding, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Row(
                          children: [
                            const BrandIcon(size: 34),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'LangPack',
                                    textScaler: TextScaler.noScaling,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.6,
                                      color: brandInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('onboarding-locale'),
                              onPressed: () {
                                setState(() => _english = !_english);
                                widget.onLocaleChanged?.call(_english);
                              },
                              child: Text(
                                _english ? '中文' : 'EN',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey('onboarding-skip'),
                              onPressed: widget.onComplete,
                              child: Text(
                                _t('跳过', 'Skip'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: wide
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: SizedBox(
                                        width: 440,
                                        height: 440,
                                        child: FittedBox(child: illustration),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 60),
                                  Expanded(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 420,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          copy,
                                          const SizedBox(height: 30),
                                          controls,
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 440,
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: math.min(
                                        300,
                                        (constraints.maxWidth - padding * 2) *
                                            .86,
                                      ),
                                      width: double.infinity,
                                      child: FittedBox(child: illustration),
                                    ),
                                    const SizedBox(height: 24),
                                    copy,
                                    const SizedBox(height: 24),
                                    controls,
                                  ],
                                ),
                              ),
                      ),
                      if (wide) const SizedBox(height: 35),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Vector-like paper illustrations made from the same UI vocabulary as the app.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.page,
    this.english = false,
  });
  final int page;
  final bool english;

  @override
  Widget build(BuildContext context) => FittedBox(
    child: SizedBox(
      width: 360,
      height: 320,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 40,
            top: 24,
            child: Container(
              width: 276,
              height: 276,
              decoration: const BoxDecoration(
                color: Color(0xFFE5F0E7),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 22,
            top: 74,
            child: Transform.rotate(
              angle: .3,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4BD77),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const Positioned(
            right: 18,
            bottom: 64,
            child: Icon(Icons.add, size: 19, color: Color(0xFF85AF99)),
          ),
          if (page == 0) ..._collect(),
          if (page == 1) ..._translate(),
          if (page == 2) ..._deliver(),
        ],
      ),
    ),
  );

  Widget _paper({
    required Widget child,
    double width = 220,
    EdgeInsets padding = const EdgeInsets.all(22),
    Color color = Colors.white,
  }) => Container(
    width: width,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: const Color(0xFFDCE8DF)),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D234B37),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: child,
  );

  Widget _label(
    String text, {
    double size = 11,
    Color color = _muted,
    FontWeight weight = FontWeight.w500,
  }) => Text(
    text,
    textScaler: TextScaler.noScaling,
    style: TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.4,
    ),
  );
  Widget _line(double width) => Container(
    width: width,
    height: 5,
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFE7EEE8),
      borderRadius: BorderRadius.circular(3),
    ),
  );

  List<Widget> _collect() => [
    Positioned(
      left: 74,
      top: 37,
      child: Transform.rotate(
        angle: -.10,
        child: Container(
          width: 217,
          height: 228,
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    ),
    Positioned(
      left: 64,
      top: 45,
      child: Transform.rotate(
        angle: .035,
        child: _paper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.subject_rounded,
                    color: brandGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  _label(
                    english ? 'Your words' : '我的产品文案',
                    color: brandInk,
                    weight: FontWeight.w600,
                  ),
                  const Spacer(),
                  const Icon(Icons.more_horiz, size: 16, color: _muted),
                ],
              ),
              const SizedBox(height: 18),
              _label(
                english ? 'Welcome back, {name}' : '欢迎回来，{name}',
                size: 14,
                color: brandInk,
              ),
              _line(153),
              _line(125),
              const SizedBox(height: 18),
              _label(
                english ? 'Save your changes' : '保存你的每一次灵感',
                size: 12,
                color: brandInk,
              ),
              _line(142),
              _line(95),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final f in ['TXT', 'MD', 'DOCX'])
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: brandCanvas,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: _label(f, size: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    Positioned(
      left: 186,
      top: 238,
      child: _paper(
        width: 153,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: brandGreen,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(
                    english ? 'Words, collected' : '文案，已收好',
                    color: brandInk,
                    size: 10,
                    weight: FontWeight.w600,
                  ),
                  _label(english ? 'Ready to begin' : '准备好下一步', size: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _translate() => [
    Positioned(
      left: 35,
      top: 45,
      child: _paper(
        width: 218,
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            _languageBadge('文', brandGreen, Colors.white),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(english ? 'SOURCE TEXT' : '原文 · 简体中文', size: 8),
                _label(
                  '你好，世界',
                  color: brandInk,
                  size: 17,
                  weight: FontWeight.w600,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    const Positioned(
      left: 158,
      top: 113,
      child: Icon(Icons.south_rounded, color: Color(0xFF80AA95), size: 25),
    ),
    Positioned(
      left: 71,
      top: 150,
      child: Transform.rotate(
        angle: -.04,
        child: _languageCard('EN', 'Hello, world', 'English'),
      ),
    ),
    Positioned(
      left: 93,
      top: 212,
      child: Transform.rotate(
        angle: .035,
        child: _languageCard('JA', 'こんにちは、世界', '日本語'),
      ),
    ),
    Positioned(
      right: 17,
      top: 91,
      child: Container(
        width: 73,
        height: 73,
        decoration: BoxDecoration(
          color: brandGreen,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: brandCanvas, width: 5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _label(
              '35',
              size: 26,
              color: Colors.white,
              weight: FontWeight.w600,
            ),
            _label(
              english ? 'languages' : '种语言',
              size: 8,
              color: const Color(0xFFCDE9D9),
            ),
          ],
        ),
      ),
    ),
  ];

  Widget _languageBadge(String code, Color background, Color foreground) =>
      Container(
        width: 35,
        height: 35,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: _label(
          code,
          color: foreground,
          size: 12,
          weight: FontWeight.w600,
        ),
      );
  Widget _languageCard(String code, String value, String language) => _paper(
    width: 234,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        _languageBadge(code, const Color(0xFFEBF3ED), brandGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(language, size: 8),
              _label(value, size: 13, color: brandInk, weight: FontWeight.w500),
            ],
          ),
        ),
        const Icon(Icons.check, size: 15, color: brandGreen),
      ],
    ),
  );

  List<Widget> _deliver() => [
    Positioned(
      left: 57,
      top: 117,
      child: Container(
        width: 255,
        height: 158,
        decoration: BoxDecoration(
          color: const Color(0xFFA6D4BA),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    ),
    Positioned(
      left: 57,
      top: 101,
      child: Container(
        width: 103,
        height: 37,
        decoration: const BoxDecoration(
          color: Color(0xFFA6D4BA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
        ),
      ),
    ),
    Positioned(
      left: 83,
      top: 35,
      child: Transform.rotate(
        angle: -.055,
        child: _paper(
          width: 205,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.data_object, size: 19, color: brandGreen),
                  const SizedBox(width: 8),
                  _label(
                    'en.json',
                    size: 11,
                    color: brandInk,
                    weight: FontWeight.w600,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _label('{', size: 13, color: brandGreen),
              _label('  "welcome":', size: 12, color: _muted),
              _label('  "Hello, {name}"', size: 12, color: brandGreen),
              _label('}', size: 13, color: brandGreen),
            ],
          ),
        ),
      ),
    ),
    Positioned(
      left: 57,
      top: 186,
      child: Container(
        width: 255,
        height: 96,
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        decoration: BoxDecoration(
          color: _mint,
          border: Border.all(color: const Color(0xFFB8D9C5)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.folder_zip_outlined, size: 26, color: brandGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _label(
                    'langpack.zip',
                    size: 14,
                    color: brandInk,
                    weight: FontWeight.w600,
                  ),
                  _label(
                    english ? 'Organized. Ready to export.' : '整理妥当，准备交付',
                    size: 9,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    Positioned(
      right: 18,
      top: 151,
      child: Container(
        width: 61,
        height: 61,
        decoration: BoxDecoration(
          color: brandGreen,
          shape: BoxShape.circle,
          border: Border.all(color: brandCanvas, width: 5),
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 29),
      ),
    ),
  ];
}
