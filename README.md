# ISRORUnified

Unified ISROR certification and billing service.

This repository now contains a single ASP.NET Core host that combines:

- ISRORBilling HTTP endpoints
- ISRORBilling NationPing TCP responder
- ISRORCertBill certification TCP server
- one merged `appsettings.json`
- one build and publish project

The compatibility surfaces are intentionally unchanged. The app is one executable and one configuration surface, but it still exposes the protocols ISROR expects.

## Project

```text
src/ISRORUnified/ISRORUnified.csproj
```

Target framework: `net8.0`.

Run locally:

```powershell
dotnet run --project src\ISRORUnified\ISRORUnified.csproj
```

Then open the operational dashboard:

```text
http://127.0.0.1:18080/
```

Build:

```powershell
dotnet build src\ISRORUnified\ISRORUnified.csproj
```

Full local verification:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\VerifyLocal.ps1
```

Compatibility audit:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\CompatibilityAudit.ps1
```

Smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\SmokeTest.ps1
```

Live certification validation with a real certification database:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\ValidateLiveCertification.ps1 -DbConfig "Data Source=127.0.0.1;TrustServerCertificate=True;Initial Catalog=SILKROAD_CERTIFICATION;User ID=sa;Password=1"
```

Use `-Serializer Old` to validate the VSRO188 serializer path. Use `-ListenAddressOverride 127.0.0.1` when the database listener address is not bindable on the validation machine, and `-TcpHostOverride 127.0.0.1` when the listener should be checked through a local address.

Live billing validation with a real account database:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\ValidateLiveBilling.ps1 -AccountDbConfig "Data Source=127.0.0.1;TrustServerCertificate=True;Initial Catalog=SILKROAD_R_ACCOUNT;User ID=sa;Password=1" -AuthService Simple -UserId "user" -PasswordHash "md5-or-stored-password-hash"
```

Use `-AuthService Full -JoymaxPortalDbConfig "..."` to validate the `A_UserLogin` path. Optional `-ValidateSecondPassword` and `-ValidateItemLock` checks exercise notification routes, but they may send mail or update account data depending on `-NotificationService`.

Live validation for a local VSRO SQL instance:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\ValidateLiveVsro.ps1
```

The VSRO helper defaults to `.\VSRO` with Windows integrated authentication. It validates certification, `Simple`, `Bypass`, `Full` when `A_UserLogin` exists, and notification routes with the non-sending `None` provider. It skips `Nemo` unless the community `TB_User` extension columns are installed.

Publish a Windows x64 bundle:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\Publish.ps1
```

The default publish is a compact self-contained single-file release. The top level should contain only:

```text
ISRORUnified.exe
appsettings.json
Database/
Patches/
```

Use `-FrameworkDependent` only if you want a smaller exe that requires the target machine to already have the .NET runtime installed. Use `-KeepSymbols`, `-KeepIisWebConfig`, or `-KeepStaticWebAssets` only when you need those deployment/debug extras.

If `artifacts/publish/win-x64/appsettings.json` already exists, the publish script preserves it so production database passwords and IP overrides are not lost. Use `-OverwriteAppSettings` to replace it from the source template.

The publish script writes to:

```text
artifacts/publish/win-x64/
```

That bundle includes `ISRORUnified.exe`, `appsettings.json`, `Database/`, and `Patches/`.

## Network Surfaces

- Billing HTTP: configured by `Kestrel:EndPoints:Http:Url`, default `http://0.0.0.0:18080`
- NationPing TCP: configured by `NationPingService:ListenAddress` and `NationPingService:ListenPort`, default `0.0.0.0:12989`
- Certification TCP: loaded from the `Certification` server body row in the certification database, unless `CertificationConfig:ListenAddressOverride` or `CertificationConfig:ListenPortOverride` is set

## Billing Endpoints

These routes are preserved:

- `/Property/Silkroad-r/checkuser.aspx?values=...`
- `/cgi/EmailPassword.asp?values=...`
- `/cgi/Email_Certification.asp?values=...`

Supported auth modes:

- `Simple`
- `Full`
- `Bypass`
- `Nemo`

Supported notification modes:

- `Email`
- `Ferre`
- `None`

## Certification

The certification server preserves the copied packet protocol, security API, database adapter, models, packet handlers, and serializers.

Serializer selection is now explicit:

```json
{
  "CertificationConfig": {
    "Serializer": "New",
    "ListenAddressOverride": "",
    "ListenPortOverride": 0
  }
}
```

Use `Old` for the VSRO188 serializer and `New` for the ISROR2015+ serializer. `New` is the default because it matched the effective behavior of the original registration order.

Leave the listener overrides empty/zero for normal production behavior. They are useful when the certification database contains a public address that cannot be bound by the current Windows host.

## Feature Toggles

Useful for local smoke tests or partial deployments:

```json
{
  "Features": {
    "Billing": true,
    "Certification": true,
    "NationPing": true
  }
}
```

## Operational Endpoints

- `/`
- `/health`
- `/status`

These operational routes bypass the Portal CGI user-agent guard. The original guard remains active for the Gateway-compatible billing routes.

## Preserved Artifacts

Certification database setup:

```text
Database/SILKROAD_CERTIFICATION.sql
```

Community billing SQL scripts:

```text
Database/CommunityProvided/
```

Certification patch files:

```text
Patches/
```

The certification SQL script drops and recreates certification tables/procedures. Treat it as setup/demo schema material, not an automatic migration to run blindly against production.

## Verified So Far

- Unified project restores and builds.
- `scripts/VerifyLocal.ps1` runs the local audit, smoke tests, validator syntax checks, vulnerability scan, publish, artifact check, and generated-log cleanup.
- `scripts/CompatibilityAudit.ps1` confirms copied billing/certification modules and preserved assets still match the downloaded originals, except for documented merge differences.
- `scripts/SmokeTest.ps1` passes against a temporary local host and ping port.
- `scripts/ValidateLiveCertification.ps1` passed against local `.\VSRO` / `SILKROAD_CERTIFICATION` with integrated authentication, `ListenAddressOverride=127.0.0.1`, and TCP listener verification on port `32000`.
- `scripts/ValidateLiveBilling.ps1` passed against local `.\VSRO` / `SILKROAD_R_ACCOUNT` for `Simple`, `Bypass`, and `Full` auth using a real `TB_User` row.
- `scripts/ValidateLiveBilling.ps1` also passed both notification CGI routes using the non-sending `None` provider.
- `scripts/ValidateLiveVsro.ps1` reruns the local live SQL validation flow and skips `Nemo` automatically when the community extension columns are absent.
- `scripts/Publish.ps1` creates a Windows x64 publish bundle.
- `/` renders a simple operational dashboard for billing, NationPing, and certification status.
- `/health` and `/status` respond when certification and ping are disabled.
- `/status` reports feature flags, auth mode, notification mode, ping listener, and selected certification serializer.
- Billing routes return expected invalid-token responses without SQL or SMTP access.
- The Portal CGI user-agent guard still returns the original browser-agent failure response for normal browser user agents.
- Auth, notification, and serializer config overrides are checked by the smoke script.
- NationPing responds to `REQ\0` with `ACK\0` on a temporary test port.
- Publish output includes the preserved certification SQL, community SQL scripts, and patch files.

Full certification protocol verification still requires a configured ISROR certification database and server components.
