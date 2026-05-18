import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';
import '../services/classifier_service.dart';
import '../services/local_storage_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences belum diinisialisasi'),
);

final localStorageProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(ref.watch(sharedPreferencesProvider)),
);

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(storage: ref.watch(localStorageProvider)),
);

final classifierServiceProvider = Provider<ImageClassifierService>(
  (ref) {
    final service = ImageClassifierService(apiService: ref.read(apiServiceProvider));
    ref.onDispose(service.dispose);
    return service;
  },
);

final profileRefreshSignalProvider = StateProvider<int>((ref) => 0);

class SessionState {
  const SessionState({
    required this.bootstrapped,
    required this.loading,
    required this.onboardingDone,
    required this.token,
    required this.user,
    required this.error,
  });

  factory SessionState.initial() {
    return const SessionState(
      bootstrapped: false,
      loading: false,
      onboardingDone: false,
      token: null,
      user: null,
      error: null,
    );
  }

  final bool bootstrapped;
  final bool loading;
  final bool onboardingDone;
  final String? token;
  final UserModel? user;
  final String? error;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  SessionState copyWith({
    bool? bootstrapped,
    bool? loading,
    bool? onboardingDone,
    String? token,
    UserModel? user,
    String? error,
    bool clearError = false,
    bool clearUser = false,
    bool clearToken = false,
  }) {
    return SessionState(
      bootstrapped: bootstrapped ?? this.bootstrapped,
      loading: loading ?? this.loading,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      token: clearToken ? null : (token ?? this.token),
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(SessionState.initial()) {
    bootstrap();
  }

  final Ref _ref;

  ApiService get _api => _ref.read(apiServiceProvider);
  LocalStorageService get _storage => _ref.read(localStorageProvider);

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, clearError: true);
    final token = _storage.token;
    final onboardingDone = _storage.onboardingDone;

    UserModel? user;
    if (token != null && token.isNotEmpty) {
      try {
        user = await _api.getProfile();
        try {
          await _api.activateSnackBox();
        } catch (_) {}
      } catch (_) {
        await _storage.clearToken();
      }
    }

    state = state.copyWith(
      bootstrapped: true,
      loading: false,
      onboardingDone: onboardingDone,
      token: user == null ? null : _storage.token,
      user: user,
      clearError: true,
      clearToken: user == null,
    );
  }

  Future<bool> completeOnboarding() async {
    await _storage.setOnboardingDone();
    state = state.copyWith(onboardingDone: true);
    return true;
  }

  Future<bool> signIn({required String email, required String password}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final auth = await _api.login(email: email, password: password);
      await _storage.saveToken(auth.token);
      try {
        await _api.activateSnackBox();
      } catch (_) {}
      state = state.copyWith(
        loading: false,
        token: auth.token,
        user: auth.user,
        clearError: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final auth = await _api.register(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      await _storage.saveToken(auth.token);
      try {
        await _api.activateSnackBox();
      } catch (_) {}
      state = state.copyWith(
        loading: false,
        token: auth.token,
        user: auth.user,
        clearError: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _api.logout();
    } catch (_) {}

    await _storage.clearToken();

    state = state.copyWith(
      loading: false,
      clearToken: true,
      clearUser: true,
      clearError: true,
    );
  }

  Future<bool> refreshUser() async {
    try {
      final user = await _api.getProfile();
      try {
        await _api.activateSnackBox();
      } catch (_) {}
      state = state.copyWith(user: user, clearError: true);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<bool> updateUser({required String name, required String email}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final user = await _api.updateProfile(name: name, email: email);
      state = state.copyWith(loading: false, user: user, clearError: true);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
