import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:neurosync_core/neurosync_core.dart';

import 'onboarding_data.dart';
import 'visuals/baseline_signal.dart';

/// Four horizontally swipeable chapters leading into authentication.
///
/// Each page is composed of four bands - meta, visual, copy, action - whose
/// heights are derived from the measured height of that chapter's copy. A tall
/// screen therefore gains a larger visual rather than a larger void, and a
/// short one compresses the visual before it can ever clip the copy or push
/// the action out of reach.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called once when the patient skips or completes onboarding.
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// The measured copy is capped so it never stretches edge to edge.
  static const double maxMeasure = 420;

  static const Duration _pageTransition = Duration(milliseconds: 420);

  final PageController _pageController = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index == onboardingChapters.length - 1;

  void _onPageChanged(int index) => setState(() => _index = index);

  void _continue() {
    if (_isLast) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: _pageTransition,
      curve: Curves.easeInOutCubic,
    );
  }

  /// Only chapters already read can be returned to; moving forward stays with
  /// Continue so the story is always read in order.
  void _goTo(int index) => _pageController.animateToPage(
        index,
        duration: _pageTransition,
        curve: Curves.easeInOutCubic,
      );

  void _finish() {
    if (_finishing) {
      return;
    }
    _finishing = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double margin = MediaQuery.sizeOf(context).width < 360 ? 20 : 24;

    return Scaffold(
      body: IntroTextScale(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _TopBar(margin: margin, onSkip: _finish, color: scheme),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: onboardingChapters.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _ChapterPage(
                    chapter: onboardingChapters[index],
                    // How far through the story this chapter sits, so a visual
                    // about accumulation accumulates as it is read.
                    progress: (index + 1) / onboardingChapters.length,
                    active: index == _index,
                    margin: margin,
                  ),
                ),
              ),
              _ActionBand(
                margin: margin,
                count: onboardingChapters.length,
                index: _index,
                onSelect: _goTo,
                label: _isLast ? 'Get Started' : 'Continue',
                onPressed: _continue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet skip affordance, deliberately out-competing nothing.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.margin,
    required this.onSkip,
    required this.color,
  });

  final double margin;
  final VoidCallback onSkip;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: margin - 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: color.onSurfaceVariant,
              minimumSize: const Size(56, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: TextStyle(
                fontSize: IntroScale.of(context).footnote,
                fontWeight: FontWeight.w400,
              ),
            ),
            child: const Text('Skip'),
          ),
        ),
      ),
    );
  }
}

/// Where the patient is in the story, and the one way forward.
class _ActionBand extends StatelessWidget {
  const _ActionBand({
    required this.margin,
    required this.count,
    required this.index,
    required this.onSelect,
    required this.label,
    required this.onPressed,
  });

  final double margin;
  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 10, margin, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            // The signal, the copy and the action all share the same left
            // edge; only its tap height is padded.
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: BaselineSignal(
              count: count,
              index: index,
              onSelect: onSelect,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: label,
            onPressed: onPressed,
            tactile: true,
          ),
        ],
      ),
    );
  }
}

/// One chapter: its visual and its copy, balanced inside the space left by the
/// top bar and the action band.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    required this.chapter,
    required this.progress,
    required this.active,
    required this.margin,
  });

  final OnboardingChapter chapter;

  /// How far through the chapters this one sits, as a fraction.
  final double progress;

  /// Whether this chapter is the one being read.
  final bool active;

  final double margin;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage>
    with SingleTickerProviderStateMixin {
  /// The copy arrives after the visual, so a page reads in order.
  late final AnimationController _copy = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  late final Animation<double> _kicker = CurvedAnimation(
    parent: _copy,
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
  );
  late final Animation<double> _headline = CurvedAnimation(
    parent: _copy,
    curve: const Interval(0.12, 0.84, curve: Curves.easeOut),
  );
  late final Animation<double> _body = CurvedAnimation(
    parent: _copy,
    curve: const Interval(0.24, 1, curve: Curves.easeOut),
  );

  static const double _gapAfterCopy = 24;

  /// Smallest the visual band is allowed to become.
  static const double _floorVisual = 104;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _copy.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ChapterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      // Arriving is always an arrival, including when returning to a chapter.
      _copy.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _copy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _ChapterCopy copy = _ChapterCopy.of(context, widget.chapter);
    final Widget visual = widget.chapter.visual(context, widget.progress);
    final Widget copyBlock = copy.build(<Animation<double>>[
      _kicker,
      _headline,
      _body,
    ]);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.margin),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // A rotated phone and a tablet both want two columns; a portrait
          // phone wants one.
          final bool wide = constraints.maxWidth > 600 ||
              constraints.maxWidth > constraints.maxHeight * 1.15;
          if (wide) {
            return _wide(constraints, copyBlock, visual);
          }
          return _portrait(constraints, copy, copyBlock, visual);
        },
      ),
    );
  }

  /// Single column: the copy is measured first, and the visual takes a share
  /// of whatever is left.
  Widget _portrait(
    BoxConstraints constraints,
    _ChapterCopy copy,
    Widget copyBlock,
    Widget visual,
  ) {
    final double available = constraints.maxHeight;
    final double measure = math.min(
      constraints.maxWidth,
      _OnboardingScreenState.maxMeasure,
    );
    // Measured with the styles the widgets will actually render with.
    final double copyHeight = copy.heightAt(measure) + 4;

    if (available < copyHeight + _gapAfterCopy + _floorVisual + 8) {
      // No room to compose at all: scroll rather than clip, and keep the copy
      // legible instead of shrinking it further.
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: _floorVisual * 1.2, child: visual),
            const SizedBox(height: _gapAfterCopy),
            SizedBox(width: measure, child: copyBlock),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    final double free = available - copyHeight - _gapAfterCopy;
    final double visualHeight =
        (free * 0.6).clamp(_floorVisual, math.max(_floorVisual, free * 0.78));
    // The copy sits slightly below the optical centre of the page.
    final double lead = ((free - visualHeight) * 0.34).clamp(0.0, free);
    final double trail = (free - visualHeight - lead).clamp(0.0, free);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(height: lead),
        SizedBox(height: visualHeight, child: visual),
        const SizedBox(height: _gapAfterCopy),
        SizedBox(width: measure, child: copyBlock),
        SizedBox(height: trail),
      ],
    );
  }

  /// Two columns, for landscape and for tablet widths: the visual keeps its
  /// height on the left, the copy gets a comfortable measure on the right.
  Widget _wide(BoxConstraints constraints, Widget copyBlock, Widget visual) {
    const double gutter = 32;
    return Row(
      children: <Widget>[
        Expanded(flex: 5, child: visual),
        const SizedBox(width: gutter),
        Expanded(
          flex: 4,
          child: Center(
            child: SizedBox(
              width: math.min(
                (constraints.maxWidth - gutter) * 4 / 9,
                _OnboardingScreenState.maxMeasure,
              ),
              // Centred while it fits, scrollable at large text sizes.
              child: SingleChildScrollView(child: copyBlock),
            ),
          ),
        ),
      ],
    );
  }
}

/// A chapter's copy, with the styles used both to measure it and to render it.
///
/// Measuring first is what lets the visual band and the surrounding space be
/// derived from the real height of the words rather than guessed, at every
/// screen size and text scale.
class _ChapterCopy {
  _ChapterCopy._({
    required this.chapter,
    required this.textScaler,
    required this.kicker,
    required this.headline,
    required this.body,
  });

  static const double gapAfterKicker = 16;
  static const double gapAfterHeadline = 14;

  factory _ChapterCopy.of(BuildContext context, OnboardingChapter chapter) {
    final IntroScale scale = IntroScale.of(context);
    // Merged with the ambient default so the measured style is exactly the
    // style the Text widgets resolve to.
    final TextStyle base = DefaultTextStyle.of(context).style;
    return _ChapterCopy._(
      chapter: chapter,
      textScaler: MediaQuery.textScalerOf(context),
      kicker: base.merge(TextStyle(
        fontSize: scale.kicker,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.8,
        color: Theme.of(context).colorScheme.primary,
      )),
      headline: base.merge(TextStyle(
        fontSize: scale.headline,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: Theme.of(context).colorScheme.onSurface,
      )),
      body: base.merge(TextStyle(
        fontSize: scale.body,
        height: 1.45,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      )),
    );
  }

  final OnboardingChapter chapter;

  /// The scaler the copy will be rendered with, so the measurement matches.
  final TextScaler textScaler;
  final TextStyle kicker;
  final TextStyle headline;
  final TextStyle body;

  /// The height this copy occupies at [width].
  double heightAt(double width) {
    double total = 0;
    for (final (String text, TextStyle style) in <(String, TextStyle)>[
      (chapter.kicker, kicker),
      (chapter.headline, headline),
      (chapter.body, body),
    ]) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: width);
      total += painter.height;
    }
    return total + gapAfterKicker + gapAfterHeadline;
  }

  Widget build(List<Animation<double>> reveal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Reveal(
            animation: reveal[0], child: Text(chapter.kicker, style: kicker)),
        const SizedBox(height: gapAfterKicker),
        _Reveal(
          animation: reveal[1],
          child: Text(chapter.headline, style: headline),
        ),
        const SizedBox(height: gapAfterHeadline),
        _Reveal(animation: reveal[2], child: Text(chapter.body, style: body)),
      ],
    );
  }
}

/// Fades a line of copy in as it rises into place.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  static const double _rise = 8;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // Transform and Opacity change how the child is painted, never how it is
      // laid out, so the measured height stays exact.
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - animation.value) * _rise),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
