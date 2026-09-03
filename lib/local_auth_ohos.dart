/// HarmonyOS local-authentication implementation for `local_auth`.
///
/// Wired automatically via `dartPluginClass` (see `pubspec.yaml`): for ohos
/// builds the Flutter tool calls [LocalAuthOhos.registerWith], which replaces
/// the default method-channel implementation from
/// `local_auth_platform_interface`. The companion native plugin
/// (`LocalAuthOhosPlugin`, registered in the app's
/// `GeneratedPluginRegistrant.ets`) drives the UserIAM `userAuth` kit:
/// system-rendered fingerprint / face / PIN prompts at trust level ATL3.
library local_auth_ohos;

import 'package:flutter/services.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

/// Bridges `local_auth` to the HarmonyOS UserIAM authentication framework.
class LocalAuthOhos extends LocalAuthPlatform {
  /// Called by the Flutter tooling on ohos at startup.
  static void registerWith() {
    LocalAuthPlatform.instance = LocalAuthOhos();
  }

  static const MethodChannel _channel =
      MethodChannel('org.tsinbeilabs.local_auth_ohos/auth');

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'authenticate',
        <String, Object?>{
          'reason': localizedReason,
          'biometricOnly': options.biometricOnly,
          'sensitiveTransaction': options.sensitiveTransaction,
          'stickyAuth': options.stickyAuth,
        },
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      throw LocalAuthException(
        code: _mapCode(e.code),
        description: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<bool> deviceSupportsBiometrics() async {
    final value = await _channel.invokeMethod<bool>('deviceSupportsBiometrics');
    return value ?? false;
  }

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async {
    final raw = await _channel.invokeListMethod<String>('getEnrolledBiometrics');
    return <BiometricType>[
      for (final type in raw ?? const <String>[])
        if (type == 'face')
          BiometricType.face
        else if (type == 'fingerprint')
          BiometricType.fingerprint
        else if (type == 'weak')
          BiometricType.weak
        else if (type == 'strong')
          BiometricType.strong,
    ];
  }

  @override
  Future<bool> isDeviceSupported() async {
    final value = await _channel.invokeMethod<bool>('isDeviceSupported');
    return value ?? false;
  }

  @override
  Future<bool> stopAuthentication() async {
    final value = await _channel.invokeMethod<bool>('stopAuthentication');
    return value ?? false;
  }

  LocalAuthExceptionCode _mapCode(String code) {
    switch (code) {
      case 'authInProgress':
        return LocalAuthExceptionCode.authInProgress;
      case 'userCanceled':
        return LocalAuthExceptionCode.userCanceled;
      case 'timeout':
        return LocalAuthExceptionCode.timeout;
      case 'noCredentialsSet':
        return LocalAuthExceptionCode.noCredentialsSet;
      case 'noBiometricsEnrolled':
        return LocalAuthExceptionCode.noBiometricsEnrolled;
      case 'noBiometricHardware':
        return LocalAuthExceptionCode.noBiometricHardware;
      case 'lockout':
        return LocalAuthExceptionCode.temporaryLockout;
      default:
        return LocalAuthExceptionCode.deviceError;
    }
  }
}
