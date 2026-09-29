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

  /// Builds the chapter's visual.
  ///
  /// [progress] is how far through the chapters the patient has read, so a
  /// visual about accumulation can accumulate as the story is read.
  final Widget Function(BuildContext context, double progress) visual;
}

/// The four onboarding chapters, in order. Content is data-driven so the
/// screen itself stays presentational.
final List<OnboardingChapter> onboardingChapters = <OnboardingChapter>[
  OnboardingChapter(
    kicker: 'DAILY MOVEMENT',
    headline: 'Understand your movement.',
    body:
        'Simple daily assessments help reveal how movement changes over time.',
    // The trace can be drawn by hand, so the patient touches the idea.
    visual: (BuildContext context, double progress) =>
        const MovementLineVisual(),
  ),
  OnboardingChapter(
    kicker: 'OVER TIME',
    headline: 'See what changes.',
    body: 'Your assessments, medication timing, and observations come together '
        'to reveal your personal pattern.',
    // Grows with the patient's position in the story.
    visual: (BuildContext context, double progress) =>
        TimelineVisual(progress: progress),
  ),
  OnboardingChapter(
    kicker: 'CONNECTED CARE',
    headline: 'Care that stays connected.',
    body:
        'Keep patients, caregivers, and clinicians aligned between appointments.',
    visual: (BuildContext context, double progress) =>
        const ConnectedCareVisual(),
  ),
  OnboardingChapter(
    kicker: 'PRIVACY',
    headline: 'Your health information stays yours.',
    body: 'Your information is protected and shared only with the people '
        'involved in your care.',
    // Sharing is a gesture here, not a claim.
    visual: (BuildContext context, double progress) =>
        const PrivacyBoundaryVisual(),
  ),
];
