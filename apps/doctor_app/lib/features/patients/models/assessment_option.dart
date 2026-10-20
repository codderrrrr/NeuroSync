/// One test a doctor can assign, and the settings they can change about it.
///
/// Every key, bound and default comes from the backend catalog, so this class
/// never invents an option. An editor built from [parameters] can only offer
/// values the assignment endpoint will accept.
class AssessmentOption {
  const AssessmentOption({
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.instructions,
    required this.executionType,
    required this.defaultDurationSeconds,
    required this.isSupported,
    required this.parameters,
  });

  factory AssessmentOption.fromJson(Map<String, dynamic> json) {
    return AssessmentOption(
      id: json['id'] as int,
      slug: json['slug'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      instructions: json['instructions'] as String,
      executionType: json['execution_type'] as String,
      defaultDurationSeconds: json['default_duration_seconds'] as int,
      isSupported: json['is_supported'] as bool,
      parameters: (json['parameters'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(AssessmentParameter.fromJson)
          .toList(growable: false),
    );
  }

  final int id;
  final String slug;
  final String title;
  final String description;
  final String instructions;
  final String executionType;
  final int defaultDurationSeconds;

  /// False for a catalog test nobody has written a runner for yet. Such a test
  /// is shown so the catalogue is honest, but it cannot be chosen.
  final bool isSupported;

  /// What a doctor may change about this test, in the order to show them.
  final List<AssessmentParameter> parameters;

  bool get isCanvas => executionType == 'canvas_task';

  /// The values this test uses when the doctor changes nothing.
  Map<String, Object> get defaultValues => <String, Object>{
        for (final AssessmentParameter parameter in parameters)
          parameter.key: parameter.defaultValue,
      };

  /// Seed an editor from what is already stored, falling back to defaults.
  ///
  /// A stored assignment always carries a complete set, so this only ever
  /// substitutes defaults for a key the catalog has since added.
  Map<String, Object> valuesFrom(Map<String, Object> stored) =>
      <String, Object>{
        for (final AssessmentParameter parameter in parameters)
          parameter.key: stored[parameter.key] ?? parameter.defaultValue,
      };
}

class AssessmentParameter {
  const AssessmentParameter({
    required this.key,
    required this.label,
    required this.kind,
    required this.defaultValue,
    this.minimum,
    this.maximum,
    this.choices = const <String>[],
    this.maxLength,
    this.helpText = '',
    this.choiceLabels = const <String, String>{},
    this.valueFormat,
  });

  factory AssessmentParameter.fromJson(Map<String, dynamic> json) {
    return AssessmentParameter(
      key: json['key'] as String,
      label: json['label'] as String,
      kind: json['kind'] as String,
      defaultValue: json['default'] as Object,
      minimum: (json['minimum'] as num?)?.toInt(),
      maximum: (json['maximum'] as num?)?.toInt(),
      choices: (json['choices'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>(),
      maxLength: (json['max_length'] as num?)?.toInt(),
      helpText: json['help_text'] as String? ?? '',
      choiceLabels: (json['choice_labels'] as Map<String, dynamic>? ?? const <String, dynamic>{})
          .map((k, v) => MapEntry(k, v as String)),
      valueFormat: json['value_format'] as String?,
    );
  }

  /// The kinds the backend declares, so the app never branches on raw strings
  /// and a new kind fails loudly here rather than rendering nothing.
  static const String kindInteger = 'integer';
  static const String kindChoice = 'choice';
  static const String kindText = 'text';

  final String key;
  final String label;
  final String kind;
  final Object defaultValue;
  final int? minimum;
  final int? maximum;
  final List<String> choices;
  final int? maxLength;
  final String helpText;
  final Map<String, String> choiceLabels;
  final String? valueFormat;

  bool get isInteger => kind == kindInteger;
  bool get isChoice => kind == kindChoice;
  bool get isText => kind == kindText;

  /// A readable rendering of one value, for the "what you set" summary.
  /// Uses API-provided choice_labels and value_format when available.
  String describe(Object value) {
    if (isChoice && value is String && choiceLabels.containsKey(value)) {
      return choiceLabels[value]!;
    }
    if (valueFormat != null) {
      return valueFormat!.replaceAll('{value}', value.toString());
    }
    // Fallback for backward compatibility
    if (isChoice && value is String) {
      return _capitalize(value);
    }
    if (isInteger && value is int && key.endsWith('percent')) {
      return '$value%';
    }
    return '$value';
  }

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
