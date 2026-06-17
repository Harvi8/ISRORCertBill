using ISRORBilling.Models.Authentication;
using ISRORBilling.Models.Notification;
using ISRORUnified.Infrastructure.Configuration;

namespace ISRORUnified.Infrastructure.ServiceRegistration;

internal static class ConfigurationValidationRegistration
{
    public static void ValidateUnifiedConfiguration(this IConfiguration configuration)
    {
        var billingEnabled = configuration.RequiredBool("Features:Billing");
        var certificationEnabled = configuration.RequiredBool("Features:Certification");
        var nationPingEnabled = configuration.RequiredBool("Features:NationPing");

        configuration.RequiredString("Kestrel:EndPoints:Http:Url");

        if (billingEnabled)
        {
            configuration.RequiredString("DbConfig:AccountDB");
            configuration.RequiredString("DbConfig:JoymaxPortalDB");
            configuration.RequiredEnum<SupportedLoginServicesEnum>("AuthService");
            configuration.RequiredEnum<NotificationServiceType>("NotificationService:Type");
            configuration.RequiredInt("ServiceCompany");
            configuration.RequiredInt("RequestTimeoutSeconds");
            configuration.RequiredString("SaltKey");
            configuration.RequiredString("PortalCGIAgentHeader");
        }

        if (certificationEnabled)
        {
            configuration.RequiredString("CertificationConfig:DbConfig");
            var serializer = configuration.RequiredString("CertificationConfig:Serializer");
            if (!serializer.Equals("Old", StringComparison.OrdinalIgnoreCase) &&
                !serializer.Equals("New", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Configuration value CertificationConfig:Serializer must be Old or New.");
            }

            var tickInterval = configuration.RequiredInt("CertificationConfig:TickIntervalMs");
            if (tickInterval <= 0)
                throw new InvalidOperationException("Configuration value CertificationConfig:TickIntervalMs must be greater than zero.");

            var listenPortOverride = configuration.RequiredInt("CertificationConfig:ListenPortOverride");
            if (listenPortOverride < 0)
                throw new InvalidOperationException("Configuration value CertificationConfig:ListenPortOverride must be zero or greater.");
        }

        if (nationPingEnabled)
        {
            configuration.RequiredString("NationPingService:ListenAddress");
            var listenPort = configuration.RequiredInt("NationPingService:ListenPort");
            if (listenPort <= 0)
                throw new InvalidOperationException("Configuration value NationPingService:ListenPort must be greater than zero.");
        }
    }
}
