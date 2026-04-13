import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_client.dart';
import '../api/api_service.dart';
import '../models/models.dart';
import '../services/device_service.dart';
import '../storage/secure_storage.dart';

// ── Singletons ────────────────────────────────────────────────────────────────

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(apiClientProvider)),
);

// ── Auth ──────────────────────────────────────────────────────────────────────

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;

  AuthState copyWith({User? user, bool? isLoading, String? error}) => AuthState(
        user:      user      ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error:     error,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;

  AuthNotifier(this._api) : super(const AuthState()) {
    _restoreSession();
  }

  /// Restore session by calling /auth/me with the stored access token.
  /// This gives us the real user id + email instead of empty strings.
  Future<void> _restoreSession() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return;

    try {
      final user = await _api.getMe();
      state = AuthState(user: user);
    } catch (_) {
      // Token expired or invalid — clear storage and stay logged out
      await SecureStorage.clearAll();
    }
  }

  /// Step 1: email + password only. Returns devOtp (non-null in dev mode).
  Future<String?> register({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final device = await DeviceService.getDeviceInfo();
      final result = await _api.register(
        email: email, password: password, device: device,
      );
      await SecureStorage.saveTokens(
        accessToken:  result.accessToken,
        refreshToken: result.refreshToken,
      );
      state = AuthState(user: result.user);
      return result.devOtp;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.userMessage);
      return null;
    }
  }

  /// Step 2: verify the OTP sent to email.
  Future<bool> verifyPhone(String otp) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final ok = await _api.verifyEmail(otp);
      if (ok && state.user != null) {
        final me = await _api.getMe();
        state = AuthState(user: me);
      }
      return ok;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.userMessage);
      return false;
    }
  }

  /// Step 3: save name + phone after email verified.
  Future<bool> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.updateProfile(fullName: fullName, phone: phone);
      state = state.copyWith(isLoading: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.userMessage);
      return false;
    }
  }

  Future<String?> resendOtp() => _api.resendOtp();

  Future<void> completeOnboarding({
    String? city,
    String? ageRange,
    List<String> preferences = const [],
    String? country,
    DateTime? dateOfBirth,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _api.completeOnboarding(
        city: city,
        ageRange: ageRange,
        preferences: preferences,
        country: country,
        dateOfBirth: dateOfBirth,
      );
      final me = await _api.getMe();
      state = AuthState(user: me);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.userMessage);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final device = await DeviceService.getDeviceInfo();
      final result = await _api.login(email: email, password: password, device: device);
      await SecureStorage.saveTokens(
        accessToken:  result.accessToken,
        refreshToken: result.refreshToken,
      );
      state = AuthState(user: result.user);
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.userMessage);
    }
  }

  Future<void> logout() async {
    await SecureStorage.clearAll();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(apiServiceProvider)),
);

// ── Wallet ────────────────────────────────────────────────────────────────────
// AsyncNotifier: data survives widget rebuilds and can be refreshed on demand.

class WalletNotifier extends AsyncNotifier<Wallet> {
  @override
  Future<Wallet> build() => ref.watch(apiServiceProvider).getWallet();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(apiServiceProvider).getWallet());
  }
}

final walletProvider = AsyncNotifierProvider<WalletNotifier, Wallet>(
  WalletNotifier.new,
);

// ── Campaigns ─────────────────────────────────────────────────────────────────

final campaignsProvider = FutureProvider<List<CampaignOffer>>((ref) async {
  return ref.watch(apiServiceProvider).getCampaigns();
});
