/// Where an assessment fell relative to a reported dose.
///
/// These mirror the backend's classification exactly. The app never computes a
/// context itself — it renders what the backend derived — so a recording can
/// never be labelled differently on the phone than it is on the server.
enum MedicationContext {
  beforeMedication,
  recentlyAfterMedication,
  laterAfterMedication,
  unknown;

  static MedicationContext fromApi(String? value) {
    switch (value) {
      case 'before_medication':
        return MedicationContext.beforeMedication;
      case 'recently_after_medication':
        return MedicationContext.recentlyAfterMedication;
      case 'later_after_medication':
        return MedicationContext.laterAfterMedication;
      case 'unknown':
      // A session stored before this layer existed has no context at all.
      // Treating that as unknown is the same statement: nothing was recorded.
      case null:
        return MedicationContext.unknown;
      default:
        throw FormatException('Unknown medication context: $value');
    }
  }

  /// Whether the patient actually reported when the dose happened.
  bool get isKnown => this != MedicationContext.unknown;

  /// A short chip label for the result screen.
  String get label {
    switch (this) {
      case MedicationContext.beforeMedication:
        return 'BEFORE MEDICATION';
      case MedicationContext.recentlyAfterMedication:
        return 'RECENTLY AFTER MEDICATION';
      case MedicationContext.laterAfterMedication:
        return 'LATER AFTER MEDICATION';
      case MedicationContext.unknown:
        return 'TIMING NOT RECORDED';
    }
  }
}

/// How much supporting information stood behind an interpretation.
///
/// A description of how much was recorded — deliberately never a percentage,
/// and never a claim about how likely something is. It exists so a patient can
/// see that "we're comparing with your own history" is a weaker statement
/// than "we're comparing with your own history recorded under the same
/// medication timing".
enum EvidenceStrength {
  insufficient,
  limited,
  moderate,
  stronger;

  static EvidenceStrength fromApi(String? value) {
    switch (value) {
      case 'insufficient':
        return EvidenceStrength.insufficient;
      case 'limited':
        return EvidenceStrength.limited;
      case 'moderate':
        return EvidenceStrength.moderate;
      case 'stronger':
        return EvidenceStrength.stronger;
      case null:
        return EvidenceStrength.insufficient;
      default:
        throw FormatException('Unknown evidence strength: $value');
    }
  }

  /// Plain-language explanation for the patient.
  String get explanation {
    switch (this) {
      case EvidenceStrength.insufficient:
        return 'There was not enough recorded information to draw a '
            'comparison.';
      case EvidenceStrength.limited:
        return 'This reading rests on a small amount of your own history.';
      case EvidenceStrength.moderate:
        return 'This reading rests on your own recorded history.';
      case EvidenceStrength.stronger:
        return 'This reading rests on your own history recorded under the '
            'same medication timing.';
    }
  }

  /// Whether the medication timing was corroborated by earlier recordings.
  bool get isMedicationAware => this == EvidenceStrength.stronger;
}

/// A relative time the patient picks from, converted to a real timestamp.
///
/// The patient picks "about 1 hour ago" because they will not remember the
/// exact minute. The app records the moment they chose; classifying what that
/// means relative to the assessment is the backend's job.
class DoseTimingChoice {
  const DoseTimingChoice({required this.label, required this.minutesAgo});

  final String label;

  /// Minutes before now that the dose is reported as having happened, or null
  /// when the patient genuinely does not know.
  final int? minutesAgo;

  bool get isUnknown => minutesAgo == null;

  /// The concrete choices offered. Deliberately coarse: an over-precise
  /// picker invites a number the patient is guessing at.
  static const List<DoseTimingChoice> options = <DoseTimingChoice>[
    DoseTimingChoice(label: 'Just now', minutesAgo: 0),
    DoseTimingChoice(label: 'About 30 minutes ago', minutesAgo: 30),
    DoseTimingChoice(label: 'About 1 hour ago', minutesAgo: 60),
    DoseTimingChoice(label: 'About 2 hours ago', minutesAgo: 120),
    DoseTimingChoice(label: 'About 3 hours ago', minutesAgo: 180),
    DoseTimingChoice(label: 'Earlier today', minutesAgo: 240),
    DoseTimingChoice(label: "I'm not sure", minutesAgo: null),
  ];
}
