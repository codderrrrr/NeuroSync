import 'package:flutter/material.dart';

import '../../core/widgets/app_buttons.dart';
import 'onboarding_data.dart';
import 'visuals/page_indicator.dart';

/// Four horizontally swipeable chapters leading into authentication.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  /// Called once when the patient skips or completes onboarding.
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index == onboardingChapters.length - 1;

  void _onPageChanged(int index) {
    setState(() => _index = index);
  }

  void _continue() {
    if (_isLast) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Quiet skip, deliberately out-competing nothing.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w400),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: onboardingChapters.length,
                itemBuilder: (BuildContext context, int index) =>
                    _ChapterPage(chapter: onboardingChapters[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: <Widget>[
                  PageIndicator(
                      count: onboardingChapters.length, activeIndex: _index),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _isLast ? 'Get Started' : 'Continue',
                    onPressed: _continue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({required this.chapter});

  final OnboardingChapter chapter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            chapter.kicker,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: chapter.visual(context)),
          const SizedBox(height: 28),
          Text(
            chapter.headline,
            style: TextStyle(
              fontSize: 34,
              height: 1.12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            chapter.body,
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
