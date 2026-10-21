/// The design system, networking and session handling shared by the NeuroSync
/// patient and doctor applications.
///
/// One place for the parts of the two applications that are genuinely the
/// same: the palette and type scale, the API client, the session token store,
/// the sign-in lifecycle and the shared widgets. What is not shared is what
/// makes each application different - the screens, the endpoints each role
/// calls, and the shape of its own user.
library;

export 'auth/auth_result.dart';
export 'auth/auth_user.dart';
// The status enum is shared; the controller itself is not, because each
// application names its own after the user it signs in as.
export 'auth/auth_controller.dart' show AuthStatus;
export 'network/api_client.dart';
export 'network/api_exception.dart';
export 'scope/app_scope_base.dart';
export 'state/api_state_controller.dart';
export 'storage/session_token_store.dart';
export 'theme/app_colors.dart';
export 'theme/app_metrics.dart';
export 'theme/app_theme.dart';
export 'theme/intro_scale.dart';
export 'theme/theme_controller.dart';
export 'theme/theme_prefs.dart';
export 'widgets/app_buttons.dart';
export 'widgets/app_card.dart';
export 'widgets/app_texts.dart';
export 'widgets/back_label.dart';
export 'widgets/bento.dart';
export 'widgets/calm_progress_ring.dart';
export 'widgets/empty_state.dart';
export 'widgets/status_tag.dart';
export 'widgets/tactile_button.dart';
export 'widgets/theme_choice.dart';
