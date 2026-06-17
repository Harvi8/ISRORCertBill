# ISRORCertBill + ISRORBilling Merge Analysis Plan

## Source Snapshot

- `Harvi8/ISRORCertBill` was downloaded from `master` into `sources/Harvi8-ISRORCertBill/ISRORCertBill-master`.
- `devtekve/ISRORBilling` was downloaded from `master` into `sources/devtekve-ISRORBilling/ISRORBilling-master`.
- `git` is not installed in this shell, so the repositories were downloaded as GitHub source archives instead of cloned with Git.

## Build Verification

- `ISRORCert` restored and built successfully.
  - Target: `net6.0`
  - Build result: success, 72 warnings.
  - Main warnings: out-of-support target framework and nullable-reference warnings in the network/security layer.
  - Vulnerability check: transitive `System.Text.Json` 6.0.0 has a high severity advisory.
- `ISRORBilling` restored and built successfully.
  - Target: `net7.0`
  - Build result: success, 2 warnings.
  - Main warnings: out-of-support target framework and vulnerable `System.Data.SqlClient` 4.8.5.
  - Vulnerability check: top-level `System.Data.SqlClient` plus several old transitive dependencies are vulnerable.

## Project Roles

### Harvi8/ISRORCertBill

This is a certification server. It is not an HTTP app. It starts a generic host, loads certification topology from SQL Server, then opens a TCP listener for ISROR server components.

Preserve these behaviors:

- SQL-backed certification model:
  - `_Content`
  - `_Division`
  - `_Farm`
  - `_FarmContent`
  - `_Module`
  - `_ServerBody`
  - `_ServerCord`
  - `_ServerMachine`
  - `_Shard`
- Stored procedures:
  - `_GetContentList`
  - `_GetDivisionList`
  - `_GetFarmList`
  - `_GetFarmContentList`
  - `_GetModuleList`
  - `_GetServerBodyList`
  - `_GetServerCordList`
  - `_GetServerMachineList`
  - `_GetShardList`
  - `_UpdateShardName`
  - `_UpdateShardMaxUser`
- TCP/security protocol stack:
  - async socket server
  - packet framing
  - Blowfish/security API
  - trusted connection setup
  - IP allow-listing from `_ServerMachine`
- Packet behavior:
  - `0x2001`: setup cord
  - `0x6003` -> `0xA003`: certification request/ack
  - `0x2005`: notify server body/server cord state
  - `0x6005` -> `0x2005`: notify request/ack
  - `0x6008` -> `0xA008`: relay routing to local handler
  - `0x6310` -> `0xA310`: shard name/max-user update
- Serializer behavior:
  - old VSRO188 serializer exists
  - new ISROR2015+ serializer exists
  - current code registers both, so the new serializer is effectively the default
- Deployment artifacts:
  - `Database/SILKROAD_CERTIFICATION.sql`
  - all `.1337` patch files in `Patches/`

### devtekve/ISRORBilling

This is an ASP.NET Core web service. It exposes Gateway-compatible HTTP endpoints, authentication modes, notification modes, and a TCP ping responder.

Preserve these behaviors:

- HTTP endpoints:
  - `/Property/Silkroad-r/checkuser.aspx?values=...`
  - `/cgi/EmailPassword.asp?values=...`
  - `/cgi/Email_Certification.asp?values=...`
- Request validation:
  - MD5 token validation with `SaltKey`
  - `ServiceCompany`
  - `RequestTimeoutSeconds`
  - optional `PortalCGIAgentHeader` user-agent guard
- Authentication modes:
  - `Simple`: checks `SILKROAD_R_ACCOUNT.dbo.TB_User`
  - `Full`: executes `GB_JoymaxPortal.dbo.A_UserLogin`
  - `Bypass`: checks user existence and ignores password
  - `Nemo`: community mode with VIP/email fields on `TB_User`
- Notification modes:
  - `Email`: SMTP email for secondary password and item lock code
  - `Ferre`: stored procedure based second password/item lock updates
  - `None`: explicit no-op mode
- Nation ping service:
  - TCP listener configured by `NationPingService:ListenAddress` and `ListenPort`
  - reads 14 bytes, transforms `REQ\0` into `ACK\0`
- Database and scripts:
  - EF Core contexts for account and portal DBs
  - Nemo community SQL scripts
  - Ferre community SQL scripts
- Logging:
  - file logging through `NReco.Logging.File`
  - unknown request logging through `GenericHandlerMiddleware`

## Recommended Unified Shape

Build one executable web host, tentatively named `ISRORUnified`, using `Microsoft.NET.Sdk.Web`.

The single process should host:

- the existing billing HTTP endpoints on Kestrel
- the billing `NationPingService`
- the certification TCP listener
- the certification async tick loop
- one shared configuration file
- one shared logging setup
- one build/publish pipeline

Keep the user-facing and server-facing protocols unchanged. "One interface" should mean one deployable service and one configuration surface, while the compatibility endpoints and TCP ports remain exactly where ISROR expects them.

## Proposed Folder Layout

```text
src/
  ISRORUnified/
    Program.cs
    appsettings.json
    Billing/
      Database/
      Models/
      Services/
      Middleware/
    Certification/
      Database/
      Logic/
      Model/
      Network/
      Services/
    Infrastructure/
      ServiceRegistration/
      Options/
Database/
  SILKROAD_CERTIFICATION.sql
  CommunityProvided/
Patches/
  patch_agent.1337
  patch_download.1337
  patch_farm.1337
  patch_game.1337
  patch_gateway.1337
  patch_global.1337
  patch_machine.1337
  patch_shard.1337
README.md
```

Keep original namespaces at first to reduce merge risk. Rename namespaces only after the combined app is tested.

## Program.cs Design

Keep `Program.cs` small:

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddUnifiedLogging(builder.Configuration);
builder.Services.AddBilling(builder.Configuration);
builder.Services.AddCertification(builder.Configuration);

var app = builder.Build();

app.MapBillingEndpoints();
app.MapHealthEndpoints();
app.UseMiddleware<GenericHandlerMiddleware>();

app.Run();
```

The registration details should move into extension methods:

- `AddBilling`
- `MapBillingEndpoints`
- `AddCertification`
- `AddUnifiedLogging`

This gives one interface without turning `Program.cs` into a junk drawer.

## Configuration Plan

Support the old config keys during the first merge, then document the unified layout.

Recommended final layout:

```json
{
  "Features": {
    "Billing": true,
    "Certification": true,
    "NationPing": true
  },
  "DbConfig": {
    "AccountDB": "...",
    "JoymaxPortalDB": "..."
  },
  "CertificationConfig": {
    "DbConfig": "...",
    "Serializer": "New",
    "TickIntervalMs": 1
  },
  "AuthService": "Simple",
  "NotificationService": {
    "Type": "Email"
  },
  "NationPingService": {
    "ListenAddress": "0.0.0.0",
    "ListenPort": 12989
  },
  "Kestrel": {
    "EndPoints": {
      "Http": {
        "Url": "http://0.0.0.0:18080"
      }
    }
  },
  "ServiceCompany": 11,
  "RequestTimeoutSeconds": 60,
  "PortalCGIAgentHeader": "Portal_CGI_Agent",
  "SaltKey": "eset5ag.nsy-g6ky5.mp",
  "AllowedHosts": "*"
}
```

The certification TCP listen host/port should continue to come from the certification database identity row, because that is how Harvi8 currently binds the correct `Certification` server body.

## Merge Phases

1. Create the unified web project.
   - Use a supported target framework.
   - Recommended first target: `net8.0` for broad deployment compatibility.
   - Use `net10.0` only if the production machine is guaranteed to have it.

2. Bring in billing unchanged.
   - Move files under `Billing/`.
   - Preserve endpoint routes exactly.
   - Preserve auth and notification enum values.
   - Build and smoke-test the three HTTP endpoints.

3. Bring in certification unchanged.
   - Move files under `Certification/`.
   - Preserve `internal` visibility by keeping it in the same project assembly.
   - Register `CertificationService`, `AsyncServerTickService`, packet handlers, `AsyncServer`, `CertificationManager`, and DB adapter.
   - Build and smoke-test service startup with a test/fake or real certification database.

4. Make certification serializer configurable.
   - Replace the duplicate `ICertificationSerializer` registrations with a factory.
   - Support `CertificationConfig:Serializer = Old|New`.
   - Default to `New` to match current effective behavior.

5. Consolidate SQL client usage.
   - Replace direct `System.Data.SqlClient` package usage with `Microsoft.Data.SqlClient` where possible.
   - Keep EF Core SQL Server provider.
   - Re-run vulnerability checks.

6. Add a tiny operational interface.
   - Add `/health`.
   - Add `/status` or `/api/status` with:
     - billing enabled/disabled
     - auth mode
     - notification mode
     - nation ping address/port
     - certification enabled/disabled
     - certification database refresh status
     - certification listener address/port once started
   - Do not replace Gateway-compatible paths.

7. Preserve deploy artifacts.
   - Copy `Database/SILKROAD_CERTIFICATION.sql`.
   - Copy Nemo/Ferre community SQL scripts.
   - Copy all `.1337` patches.
   - Update README to explain one service, three network surfaces:
     - HTTP billing on `18080`
     - TCP nation ping on `12989`
     - TCP certification from DB, commonly `32000`

8. Verify behavior.
   - `dotnet restore`
   - `dotnet build`
   - dependency vulnerability check
   - endpoint contract checks
   - serializer selection checks
   - startup checks with missing DB, bad DB, and valid DB
   - manual Gateway/server integration test

## Main Risks

- The certification code has protocol-sensitive byte serialization. Avoid clever refactors around packet writing until integration tests exist.
- The certification service currently silently does not listen when database refresh fails. In the unified service, expose this in status/health.
- The current serializer registration is ambiguous to readers. Make the selected serializer explicit.
- `System.Data.SqlClient` and older transitive packages have vulnerability advisories. The merge should modernize dependencies before release.
- Both original target frameworks are out of support. Do not ship the merged app on `net6.0` or `net7.0`.
- The certification SQL script is destructive because it drops and recreates tables/procedures. Keep it clearly labeled as setup/demo schema, not an automatic migration.
- The `Ferre` notification SQL stores sensitive item lock data in plaintext by design. Preserve it for compatibility, but document the risk.

## Acceptance Checklist

- A single executable starts all enabled services.
- Existing Gateway HTTP URLs still return the same response formats.
- `Simple`, `Full`, `Bypass`, and `Nemo` auth modes still work.
- `Email`, `Ferre`, and `None` notification modes still work.
- Nation ping still answers `REQ` with `ACK`.
- Certification still accepts only configured server machine IPs.
- Certification still handles setup, certificate, notify, relay, and shard update packets.
- Old and new certification serializers are both available by config.
- All SQL scripts and patch files remain included.
- Build has no errors.
- Dependency vulnerability count is reduced or explicitly accepted.
