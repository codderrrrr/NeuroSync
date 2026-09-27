import 'package:flutter/material.dart';

import 'visuals/connected_care_visual.dart';
import 'visuals/movement_line_visual.dart';
import 'visuals/privacy_boundary_visual.dart';
import 'visuals/timeline_visual.dart';

/// One chapter of the onboarding story: Movement, Change, Connection, Trust.
class OnboardingChapter {
  OnboardingChapter({
    required this.kicker,
    required this.headline,
    required this.body,
    required this.visual,
  });

  /// Small restrained label above the visual.
  final String kicker;

  final String headline;
  final String body;

  /// The chapter's visual composition.
  final WidgetBuilder visual;
}

/// The four onboarding chapters, in order. Content is data-driven so the
/// screen itself stays presentational.
final List<OnboardingChapter> onboardingChapters = <OnboardingChapter>[
  OnboardingChapter(
    kicker: 'DAILY MOVEMENT',
    headline: 'Understand your movement.',
    body:
        'Simple daily assessments help reveal how movement changes over time.',
    visual: _visual(MovementLineVisual.new),
  ),
  OnboardingChapter(
    kicker: 'OVER TIME',
    headline: 'See what changes.',
    body: 'Your assessments, medication timing, and observations come together '
        'to reveal your personal pattern.',
    visual: _visual(TimelineVisual.new),
  ),
  OnboardingChapter(
    kicker: 'CONNECTED CARE',
    headline: 'Care that stays connected.',
    body:
        'Keep patients, caregivers, and clinicians aligned between appointments.',
    visual: _visual(ConnectedCareVisual.new),
  ),
  OnboardingChapter(
    kicker: 'PRIVACY',
    headline: 'Your health information stays yours.',
    body: 'Your information is protected and shared only with the people '
        'involved in your care.',
    visual: _visual(PrivacyBoundaryVisual.new),
  ),
];

WidgetBuilder _visual(Widget Function() factory) =>
    (BuildContext context) => factory();
