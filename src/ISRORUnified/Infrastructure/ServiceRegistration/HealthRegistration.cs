using ISRORCert.Model;
using ISRORCert;
using ISRORBilling.Models.Ping;
using ISRORUnified.Infrastructure.Configuration;
using Microsoft.Extensions.Options;
using System.Net;
using System.Text;

namespace ISRORUnified.Infrastructure.ServiceRegistration;

internal static class HealthRegistration
{
    public static WebApplication MapHealthEndpoints(this WebApplication app)
    {
        app.MapGet("/", (IConfiguration configuration, IServiceProvider services) =>
        {
            var status = GetStatus(configuration, services);
            return Results.Content(RenderDashboard(status), "text/html; charset=utf-8");
        });

        app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

        app.MapGet("/status", (IConfiguration configuration, IServiceProvider services) =>
        {
            return Results.Ok(GetStatus(configuration, services));
        });

        return app;
    }

    private static UnifiedStatus GetStatus(IConfiguration configuration, IServiceProvider services)
    {
        var certificationManager = services.GetService<CertificationManager>();
        var pingOptions = services.GetService<IOptions<NationPingServiceOptions>>()?.Value;
        var certificationOptions = services.GetService<IOptions<CertificationConfig>>()?.Value;
        var certificationIdentity = certificationManager?.Identity;
        var billingEnabled = configuration.RequiredBool("Features:Billing");
        var nationPingEnabled = configuration.RequiredBool("Features:NationPing");
        var certificationEnabled = configuration.RequiredBool("Features:Certification");
        var certificationListenAddress = string.IsNullOrWhiteSpace(certificationOptions?.ListenAddressOverride)
            ? certificationIdentity?.Machine?.PublicIP
            : certificationOptions.ListenAddressOverride;
        var certificationListenPort = certificationOptions?.ListenPortOverride > 0
            ? (int?)certificationOptions.ListenPortOverride
            : certificationIdentity?.ListenerPort;
        var configuredNationPingPort = int.TryParse(configuration["NationPingService:ListenPort"], out var parsedNationPingPort)
            ? parsedNationPingPort
            : (int?)null;

        return new UnifiedStatus(
            new BillingStatus(
                billingEnabled,
                billingEnabled ? configuration.RequiredString("AuthService") : configuration["AuthService"] ?? string.Empty,
                billingEnabled ? configuration.RequiredString("NotificationService:Type") : configuration["NotificationService:Type"] ?? string.Empty,
                configuration.RequiredString("Kestrel:EndPoints:Http:Url")),
            new NationPingStatus(
                nationPingEnabled,
                nationPingEnabled ? pingOptions?.ListenAddress ?? configuration.RequiredString("NationPingService:ListenAddress") : configuration["NationPingService:ListenAddress"] ?? string.Empty,
                nationPingEnabled ? pingOptions?.ListenPort ?? configuration.RequiredInt("NationPingService:ListenPort") : configuredNationPingPort),
            new CertificationStatus(
                certificationEnabled,
                certificationIdentity is not null,
                certificationEnabled ? configuration.RequiredString("CertificationConfig:Serializer") : configuration["CertificationConfig:Serializer"] ?? string.Empty,
                certificationListenAddress,
                certificationListenPort));
    }

    private static string RenderDashboard(UnifiedStatus status)
    {
        var html = new StringBuilder();
        html.AppendLine("<!doctype html>");
        html.AppendLine("<html lang=\"en\">");
        html.AppendLine("<head>");
        html.AppendLine("<meta charset=\"utf-8\">");
        html.AppendLine("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        html.AppendLine("<title>ISROR Unified</title>");
        html.AppendLine("<style>");
        html.AppendLine(":root{color-scheme:light;--ink:#15191f;--muted:#5a6472;--line:#d7dde5;--bg:#f5f7fa;--panel:#ffffff;--ok:#167a4a;--off:#7b8491;--warn:#b45f06;--link:#195da8;}");
        html.AppendLine("*{box-sizing:border-box}");
        html.AppendLine("body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 Segoe UI,Arial,sans-serif;}");
        html.AppendLine("main{max-width:1040px;margin:0 auto;padding:28px 18px 40px;}");
        html.AppendLine("header{display:flex;align-items:flex-start;justify-content:space-between;gap:18px;margin-bottom:22px;border-bottom:1px solid var(--line);padding-bottom:18px;}");
        html.AppendLine("h1{margin:0;font-size:26px;font-weight:650;}");
        html.AppendLine("p{margin:6px 0 0;color:var(--muted);}");
        html.AppendLine("a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}");
        html.AppendLine(".grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;}");
        html.AppendLine("section{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;min-width:0;}");
        html.AppendLine("h2{margin:0 0 12px;font-size:16px;font-weight:650;}");
        html.AppendLine("dl{margin:0;display:grid;grid-template-columns:minmax(92px,40%) minmax(0,1fr);gap:8px 12px;}");
        html.AppendLine("dt{color:var(--muted);}dd{margin:0;min-width:0;overflow-wrap:anywhere;}");
        html.AppendLine(".badge{display:inline-flex;align-items:center;gap:6px;border:1px solid var(--line);border-radius:999px;padding:5px 10px;background:#fff;font-weight:600;white-space:nowrap;}");
        html.AppendLine(".dot{width:9px;height:9px;border-radius:50%;background:var(--off);display:inline-block;}.on .dot{background:var(--ok)}.pending .dot{background:var(--warn)}");
        html.AppendLine(".links{display:flex;gap:10px;flex-wrap:wrap;justify-content:flex-end}.links a{border:1px solid var(--line);border-radius:6px;background:#fff;padding:7px 10px;}");
        html.AppendLine("@media (max-width:760px){header{display:block}.links{justify-content:flex-start;margin-top:14px}.grid{grid-template-columns:1fr}main{padding:20px 14px 30px}}");
        html.AppendLine("</style>");
        html.AppendLine("</head>");
        html.AppendLine("<body>");
        html.AppendLine("<main>");
        html.AppendLine("<header>");
        html.AppendLine("<div><h1>ISROR Unified</h1><p>Certification, billing, and ping service status.</p></div>");
        html.AppendLine("<nav class=\"links\" aria-label=\"Operational links\"><a href=\"/status\">JSON status</a><a href=\"/health\">Health</a></nav>");
        html.AppendLine("</header>");
        html.AppendLine("<div class=\"grid\">");
        AppendBilling(html, status.Billing);
        AppendNationPing(html, status.NationPing);
        AppendCertification(html, status.Certification);
        html.AppendLine("</div>");
        html.AppendLine("</main>");
        html.AppendLine("</body>");
        html.AppendLine("</html>");
        return html.ToString();
    }

    private static void AppendBilling(StringBuilder html, BillingStatus billing)
    {
        AppendSectionStart(html, "Billing", billing.Enabled ? "Enabled" : "Disabled", billing.Enabled ? "on" : string.Empty);
        AppendRow(html, "HTTP", billing.Http);
        AppendRow(html, "Auth", billing.AuthService);
        AppendRow(html, "Notify", billing.NotificationService);
        AppendSectionEnd(html);
    }

    private static void AppendNationPing(StringBuilder html, NationPingStatus nationPing)
    {
        AppendSectionStart(html, "NationPing", nationPing.Enabled ? "Enabled" : "Disabled", nationPing.Enabled ? "on" : string.Empty);
        AppendRow(html, "Address", nationPing.ListenAddress);
        AppendRow(html, "Port", nationPing.ListenPort?.ToString() ?? string.Empty);
        AppendSectionEnd(html);
    }

    private static void AppendCertification(StringBuilder html, CertificationStatus certification)
    {
        var badgeText = certification.Enabled
            ? certification.Refreshed ? "Ready" : "Waiting for DB"
            : "Disabled";
        var badgeClass = certification.Enabled
            ? certification.Refreshed ? "on" : "pending"
            : string.Empty;

        AppendSectionStart(html, "Certification", badgeText, badgeClass);
        AppendRow(html, "Serializer", certification.Serializer);
        AppendRow(html, "Address", certification.ListenAddress ?? string.Empty);
        AppendRow(html, "Port", certification.ListenPort?.ToString() ?? string.Empty);
        AppendSectionEnd(html);
    }

    private static void AppendSectionStart(StringBuilder html, string title, string badgeText, string badgeClass)
    {
        html.AppendLine("<section>");
        html.Append("<h2>").Append(WebUtility.HtmlEncode(title)).AppendLine("</h2>");
        html.Append("<p class=\"badge ");
        html.Append(WebUtility.HtmlEncode(badgeClass));
        html.Append("\"><span class=\"dot\" aria-hidden=\"true\"></span>");
        html.Append(WebUtility.HtmlEncode(badgeText));
        html.AppendLine("</p>");
        html.AppendLine("<dl>");
    }

    private static void AppendRow(StringBuilder html, string label, string value)
    {
        html.Append("<dt>").Append(WebUtility.HtmlEncode(label)).Append("</dt><dd>");
        html.Append(WebUtility.HtmlEncode(string.IsNullOrWhiteSpace(value) ? "-" : value));
        html.AppendLine("</dd>");
    }

    private static void AppendSectionEnd(StringBuilder html)
    {
        html.AppendLine("</dl>");
        html.AppendLine("</section>");
    }

    private sealed record UnifiedStatus(BillingStatus Billing, NationPingStatus NationPing, CertificationStatus Certification);
    private sealed record BillingStatus(bool Enabled, string AuthService, string NotificationService, string Http);
    private sealed record NationPingStatus(bool Enabled, string ListenAddress, int? ListenPort);
    private sealed record CertificationStatus(bool Enabled, bool Refreshed, string Serializer, string? ListenAddress, int? ListenPort);
}
