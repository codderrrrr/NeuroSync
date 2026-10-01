/// The signed-in doctor, including the personal link code patients type.
class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
    this.code,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      code: json['code'] as String?,
    );
  }

  final int id;
  final String name;
  final String email;
  final DateTime createdAt;

  /// The doctor's shareable link code, or null when the account predates
  /// codes and one has not been issued yet.
  final String? code;

  /// First word of the doctor's name, used for the home greeting.
  String get firstName {
    final String trimmed = name.trim();
    final int separator = trimmed.indexOf(' ');
    return separator == -1 ? trimmed : trimmed.substring(0, separator);
  }
}
