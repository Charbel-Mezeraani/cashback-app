import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:math';

/// Collects stable device info for fraud detection.
/// The device_id is stable across app restarts and is stored in secure storage.
class DeviceService {
  static const _storage   = FlutterSecureStorage();
  static const _deviceKey = 'device_id';

  /// Returns a map of device info to send with login/register.
  static Future<Map<String, String?>> getDeviceInfo() async {
    final deviceId  = await _getOrCreateDeviceId();
    final platform  = _getPlatform();
    final osVersion = await _getOsVersion();
    final appVersion = await _getAppVersion();

    return {
      'device_id':   deviceId,
      'platform':    platform,
      'os_version':  osVersion,
      'app_version': appVersion,
    };
  }

  /// Stable device ID: read from secure storage, create once if absent.
  static Future<String> _getOrCreateDeviceId() async {
    var id = await _storage.read(key: _deviceKey);
    if (id != null) return id;

    // Try to use the OS device identifier first
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        id = info.id; // Android ID
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        id = info.identifierForVendor;
      }
    } catch (_) {
      // Fallback for Linux / unsupported platforms
    }

    // Fallback: generate a random UUID and persist it
    id ??= _generateUuid();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  static String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS)     return 'ios';
    if (Platform.isLinux)   return 'linux';
    if (Platform.isMacOS)   return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  static Future<String> _getOsVersion() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return 'iOS ${info.systemVersion}';
      } else if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return info.prettyName;
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  static Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '1.0.0';
    }
  }

  static String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    return [
      bytes.sublist(0, 4).map(hex).join(),
      bytes.sublist(4, 6).map(hex).join(),
      bytes.sublist(6, 8).map(hex).join(),
      bytes.sublist(8, 10).map(hex).join(),
      bytes.sublist(10, 16).map(hex).join(),
    ].join('-');
  }
}
