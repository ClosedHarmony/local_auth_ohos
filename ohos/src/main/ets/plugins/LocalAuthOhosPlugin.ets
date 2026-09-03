/*
 * Copyright (c) 2026 TsinbeiLabs
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec,
} from '@ohos/flutter_ohos';
import userAuth from '@ohos.userIAM.userAuth';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG: string = 'LocalAuthOhosPlugin';
const CHANNEL_NAME: string = 'org.tsinbeilabs.local_auth_ohos/auth';

/**
 * Native half of local_auth_ohos: wraps the UserIAM `userAuth` kit.
 *
 * Credential selection order: fingerprint -> face -> PIN (PIN only when the
 * caller allows non-biometric fallback, i.e. `biometricOnly` is false).
 * Authentication runs at trust level ATL3 with the system-rendered prompt.
 */
export default class LocalAuthOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private currentInstance: userAuth.AuthInstance | null = null;

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
      StandardMethodCodec.INSTANCE,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    if (this.currentInstance != null) {
      try {
        this.currentInstance.cancel();
      } catch (e) {
        // Best effort.
      }
      this.currentInstance = null;
    }
  }

  getUniqueClassName(): string {
    return TAG;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'authenticate': {
          this.authenticate(call, result);
          break;
        }
        case 'deviceSupportsBiometrics': {
          result.success(
            this.isAvailable(userAuth.UserAuthType.FINGERPRINT) ||
              this.isAvailable(userAuth.UserAuthType.FACE),
          );
          break;
        }
        case 'getEnrolledBiometrics': {
          result.success(this.enrolledBiometrics());
          break;
        }
        case 'isDeviceSupported': {
          result.success(
            this.isAvailable(userAuth.UserAuthType.FINGERPRINT) ||
              this.isAvailable(userAuth.UserAuthType.FACE) ||
              this.isAvailable(userAuth.UserAuthType.PIN),
          );
          break;
        }
        case 'stopAuthentication': {
          result.success(this.stop());
          break;
        }
        default: {
          result.notImplemented();
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      result.error('deviceError', err.message ?? `${e}`, null);
    }
  }

  /**
   * `getAvailableStatus` throws a BusinessError when the credential is
   * unavailable (12500005 type unsupported, 12500006 trust level
   * unsupported, 12500010 not enrolled, ...) and returns normally when the
   * credential is ready.
   */
  private isAvailable(type: userAuth.UserAuthType): boolean {
    try {
      userAuth.getAvailableStatus(type, userAuth.AuthTrustLevel.ATL3);
      return true;
    } catch (e) {
      return false;
    }
  }

  private enrolledBiometrics(): string[] {
    const out: string[] = [];
    if (this.isAvailable(userAuth.UserAuthType.FINGERPRINT)) {
      out.push('fingerprint');
    }
    if (this.isAvailable(userAuth.UserAuthType.FACE)) {
      out.push('face');
    }
    if (this.isAvailable(userAuth.UserAuthType.PIN)) {
      out.push('weak');
    }
    return out;
  }

  private stop(): boolean {
    if (this.currentInstance == null) {
      return false;
    }
    try {
      this.currentInstance.cancel();
      this.currentInstance = null;
      return true;
    } catch (e) {
      this.currentInstance = null;
      return false;
    }
  }

  private authenticate(call: MethodCall, result: MethodResult): void {
    if (this.currentInstance != null) {
      result.error('authInProgress', 'An authentication attempt is already in progress', null);
      return;
    }
    const map: ESObject = call.args;
    const biometricOnly: boolean = map.get('biometricOnly') === true;

    let authType: number = -1;
    if (this.isAvailable(userAuth.UserAuthType.FINGERPRINT)) {
      authType = userAuth.UserAuthType.FINGERPRINT;
    } else if (this.isAvailable(userAuth.UserAuthType.FACE)) {
      authType = userAuth.UserAuthType.FACE;
    } else if (!biometricOnly && this.isAvailable(userAuth.UserAuthType.PIN)) {
      authType = userAuth.UserAuthType.PIN;
    }

    if (authType < 0) {
      result.error(
        biometricOnly ? 'noBiometricsEnrolled' : 'noCredentialsSet',
        'No enrolled credential is available on this device',
        null,
      );
      return;
    }

    try {
      // Challenge is unused by the caller; an empty buffer skips token
      // binding verification.
      const challenge = new Uint8Array(16);
      const instance: userAuth.AuthInstance = userAuth.getAuthInstance(
        challenge,
        authType as userAuth.UserAuthType,
        userAuth.AuthTrustLevel.ATL3,
      );
      this.currentInstance = instance;
      const callback: userAuth.IAuthCallback = {
        onResult: (authResult: userAuth.UserAuthResult): void => {
          this.currentInstance = null;
          const code: number = authResult.result;
          if (code === userAuth.UserAuthResultCode.SUCCESS) {
            result.success(true);
          } else if (code === userAuth.UserAuthResultCode.CANCELED) {
            result.error('userCanceled', 'Authentication canceled by the user', null);
          } else if (code === userAuth.UserAuthResultCode.TIMEOUT) {
            result.error('timeout', 'Authentication timed out', null);
          } else if (code === userAuth.UserAuthResultCode.FAIL) {
            // Challenge failed; the user may retry.
            result.success(false);
          } else {
            result.error('deviceError', `Authentication failed with code ${code}`, null);
          }
        },
      };
      instance.on('result', callback);
      instance.start();
    } catch (e) {
      this.currentInstance = null;
      const err = e as BusinessError;
      result.error('deviceError', `Unable to start authentication: ${err.code} ${err.message}`, null);
    }
  }
}
