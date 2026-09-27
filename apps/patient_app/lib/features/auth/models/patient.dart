/// Basic patient profile returned by the API.
class Patient {
  const Patient({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int id;
  final String email;
  final String name;
  final DateTime createdAt;

  /// First word of the patient's name, used for the home greeting.
  String get firstName {
    final String trimmed = name.trim();
    final int separator = trimmed.indexOf(' ');
    return separator == -1 ? trimmed : trimmed.substring(0, separator);
  }
}
