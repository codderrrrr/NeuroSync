/// The signed-in user, whichever role they signed in as.
///
/// A patient and a doctor share the same identity fields, so the parts that
/// are the same live here and each application adds only what is its own.
abstract class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
  });

  final int id;
  final String email;
  final String name;
  final DateTime createdAt;

  /// First word of the user's name, used for the home greeting.
  String get firstName {
    final String trimmed = name.trim();
    final int separator = trimmed.indexOf(' ');
    return separator == -1 ? trimmed : trimmed.substring(0, separator);
  }
}
