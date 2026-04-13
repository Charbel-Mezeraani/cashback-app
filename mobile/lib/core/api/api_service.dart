import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/models.dart';
import 'api_client.dart';

/// All API calls in one place.
/// Screens and providers talk to this — never to ApiClient directly.
class ApiService {
  final ApiClient _client;
  const ApiService(this._client);

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// Step 1: email + password → get token + dev OTP
  Future<({User user, String accessToken, String refreshToken, String? devOtp})> register({
    required String email,
    required String password,
    Map<String, String?>? device,
  }) async {
    final data = await _client.post('/auth/register', body: {
      'email':    email,
      'password': password,
      if (device != null) 'device': device,
    });
    return (
      user:         User.fromJson(data['user'] as Map<String, dynamic>),
      accessToken:  data['access_token']  as String,
      refreshToken: data['refresh_token'] as String,
      devOtp:       data['_dev_otp']      as String?,
    );
  }

  /// Step 2: verify email OTP
  Future<bool> verifyEmail(String otp) async {
    final data = await _client.post('/auth/verify-email', body: {'otp': otp});
    return (data['email_verified'] as bool?) ?? false;
  }

  // Keep old name as alias so nothing else breaks during transition
  Future<bool> verifyPhone(String otp) => verifyEmail(otp);

  Future<String?> resendOtp() async {
    final data = await _client.post('/auth/resend-otp', body: {});
    return data['_dev_otp'] as String?;
  }

  /// Step 3: save name + phone after email verified
  Future<void> updateProfile({
    required String fullName,
    required String phone,
  }) async {
    await _client.patch('/auth/profile', body: {
      'full_name': fullName,
      'phone':     phone,
    });
  }

  Future<void> completeOnboarding({
    String? city,
    String? ageRange,
    List<String> preferences = const [],
    String? country,
    DateTime? dateOfBirth,
  }) async {
    await _client.patch('/auth/onboarding', body: {
      if (city != null) 'city': city,
      if (ageRange != null) 'age_range': ageRange,
      'preferences': preferences,
      if (country != null) 'country': country,
      if (dateOfBirth != null)
        'date_of_birth':
            '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}',
    });
  }

  Future<({User user, String accessToken, String refreshToken})> login({
    required String email,
    required String password,
    Map<String, String?>? device,
  }) async {
    final data = await _client.post('/auth/login', body: {
      'email':    email,
      'password': password,
      if (device != null) 'device': device,
    });
    return (
      user:         User.fromJson(data['user'] as Map<String, dynamic>),
      accessToken:  data['access_token']  as String,
      refreshToken: data['refresh_token'] as String,
    );
  }

  Future<User> getMe() async {
    final data = await _client.get('/auth/me');
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  // ── Products ──────────────────────────────────────────────────────────────

  Future<Product> getProductByBarcode(String barcode) async {
    final data = await _client.get('/products/$barcode');
    return Product.fromJson(data);
  }

  // ── Receipts ──────────────────────────────────────────────────────────────

  /// Step 1: get a presigned S3 URL.
  Future<({String s3Key, String uploadUrl})> getUploadUrl(String mimeType) async {
    final data = await _client.post('/receipts/upload-url',
        body: {'mime_type': mimeType});
    return (
      s3Key:     data['s3_key']     as String,
      uploadUrl: data['upload_url'] as String,
    );
  }

  /// Step 2: register the receipt row after the image has been uploaded to S3.
  Future<Receipt> submitReceipt({
    required String s3Key,
    required List<int> imageBytes,
  }) async {
    final imageHash = sha256.convert(imageBytes).toString();
    final data = await _client.post('/receipts',
        body: {'s3_key': s3Key, 'image_hash': imageHash});
    return Receipt.fromJson(data);
  }

  /// Poll until OCR is done or failed (caller drives the loop).
  Future<Receipt> getReceipt(String receiptId) async {
    final data = await _client.get('/receipts/$receiptId');
    return Receipt.fromJson(data);
  }

  // ── Claims ────────────────────────────────────────────────────────────────

  Future<Claim> submitClaim({
    required String receiptId,
    required String productId,
  }) async {
    final data = await _client.post('/claims',
        body: {'receipt_id': receiptId, 'product_id': productId});
    return Claim.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> getClaims() async {
    final data = await _client.get('/claims');
    return (data['claims'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  // ── Campaigns ─────────────────────────────────────────────────────────────

  Future<List<CampaignOffer>> getCampaigns() async {
    final data = await _client.get('/products/campaigns/active');
    return (data['campaigns'] as List<dynamic>)
        .map((e) => CampaignOffer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Wallet ────────────────────────────────────────────────────────────────

  Future<Wallet> getWallet() async {
    final data = await _client.get('/wallet');
    return Wallet.fromJson(data);
  }
}
