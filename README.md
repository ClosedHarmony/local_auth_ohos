# local_auth_ohos

HarmonyOS (OpenHarmony / HarmonyOS NEXT) local-authentication implementation
for [`local_auth`](https://pub.dev/packages/local_auth), backed by the UserIAM
`userAuth` kit (`@ohos.userIAM.userAuth`).

## How it works

- **Dart side** — `LocalAuthOhos extends LocalAuthPlatform`
  (`local_auth_platform_interface`). Declared as `dartPluginClass` with
  `implements: local_auth`, so the Flutter tool registers it automatically for
  ohos builds; no changes to the app-facing `local_auth` package are needed.
- **Native side** — `LocalAuthOhosPlugin` serves the method channel
  `org.tsinbeilabs.local_auth_ohos/auth`:
  | Method | Behavior |
  |---|---|
  | `authenticate` | picks the first available credential (fingerprint → face → PIN unless `biometricOnly`), runs `userAuth.getAuthInstance(..., ATL3)` with the system prompt |
  | `deviceSupportsBiometrics` | fingerprint or face available |
  | `getEnrolledBiometrics` | `fingerprint` / `face` / `weak` (PIN) as enrolled |
  | `isDeviceSupported` | any credential available |
  | `stopAuthentication` | cancels the in-flight `AuthInstance` |

Error mapping to `LocalAuthExceptionCode`: `userCanceled`, `timeout`,
`noCredentialsSet`, `noBiometricsEnrolled`, `authInProgress`, `deviceError`.

## Usage

```yaml
dependencies:
  local_auth: ^3.0.2
  local_auth_ohos:
    git:
      url: https://github.com/TsinbeiLabs/local_auth_ohos.git
      ref: main
```

Register the native plugin in `GeneratedPluginRegistrant.ets`:

```typescript
import LocalAuthOhosPlugin from 'local_auth_ohos';
// ...
flutterEngine.getPlugins()?.add(new LocalAuthOhosPlugin());
```

The plugin declares `ohos.permission.ACCESS_BIOMETRIC` in its `module.json5`;
the permission is merged into the app at build time.

## Notes & limitations

- Authentication runs at trust level **ATL3** (sufficient for app unlock /
  local confirmation flows). ATL4 (payment-grade) is not targeted.
- `AuthMessages` customization is ignored: the prompt UI is fully
  system-rendered by the UserIAM framework.
- Requires a device with enrolled credentials; `getAvailableStatus` error
  codes drive the availability checks.

## License

Apache-2.0.
