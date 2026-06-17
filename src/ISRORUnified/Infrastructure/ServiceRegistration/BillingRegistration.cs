using ISRORBilling.Database;
using ISRORBilling.Database.CommunityProvided.Nemo07;
using ISRORBilling.Models.Authentication;
using ISRORBilling.Models.Notification;
using ISRORBilling.Models.Options;
using ISRORBilling.Models.Ping;
using ISRORBilling.Services.Authentication;
using ISRORBilling.Services.Authentication.CommunityProvided.Nemo07;
using ISRORBilling.Services.Notification;
using ISRORBilling.Services.Notification.CommunityProvided;
using ISRORBilling.Services.Ping;
using ISRORUnified.Infrastructure.Configuration;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ISRORUnified.Infrastructure.ServiceRegistration;

internal static class BillingRegistration
{
    public static IServiceCollection AddBilling(this IServiceCollection services, IConfiguration configuration)
    {
        if (configuration.RequiredBool("Features:Billing"))
        {
            services.AddDbContext<AccountContext>(options =>
            {
                options.UseSqlServer(configuration.RequiredString("DbConfig:AccountDB"));
                options.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
            });

            services.AddDbContext<JoymaxPortalContext>(options =>
            {
                options.UseSqlServer(configuration.RequiredString("DbConfig:JoymaxPortalDB"));
                options.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
            });

            services.AddNotificationService(configuration);
            services.AddAuthenticationService(configuration);
        }

        if (configuration.RequiredBool("Features:NationPing"))
        {
            services.Configure<NationPingServiceOptions>(configuration.GetSection("NationPingService"));
            services.AddHostedService<NationPingService>();
        }

        return services;
    }

    public static WebApplication MapBillingEndpoints(this WebApplication app)
    {
        if (!app.Configuration.RequiredBool("Features:Billing"))
            return app;

        var serviceCompany = app.Configuration.RequiredInt("ServiceCompany");
        var requestTimeoutSeconds = app.Configuration.RequiredInt("RequestTimeoutSeconds");
        var saltKey = app.Configuration.RequiredString("SaltKey");

        app.MapGet("/Property/Silkroad-r/checkuser.aspx",
            ([FromQuery] string values, [FromServices] ILogger<Program> logger, [FromServices] IAuthService authService) =>
            {
                logger.LogDebug("Received in params: {Values}", values);
                var request = new CheckUserRequest(values, saltKey, serviceCompany, requestTimeoutSeconds);

                return authService.Login(request).ToString();
            });

        app.MapGet("/cgi/EmailPassword.asp",
            async ([FromQuery] string values, [FromServices] ILogger<Program> logger,
                [FromServices] INotificationService notificationService) =>
            {
                logger.LogDebug("Received in params: {Values}", values);
                var request = new SendCodeRequest(values, saltKey);

                return await notificationService.SendSecondPassword(request) ? 0 : -1;
            });

        app.MapGet("/cgi/Email_Certification.asp",
            async ([FromQuery] string values, [FromServices] ILogger<Program> logger,
                [FromServices] INotificationService notificationService) =>
            {
                logger.LogDebug("Received in params: {Values}", values);
                var request = new SendCodeRequest(values, saltKey);

                return await notificationService.SendItemLockCode(request) ? 0 : -1;
            });

        return app;
    }

    private static IServiceCollection AddNotificationService(this IServiceCollection services, IConfiguration configuration)
    {
        var notificationServiceType = configuration.RequiredEnum<NotificationServiceType>("NotificationService:Type");
        switch (notificationServiceType)
        {
            case NotificationServiceType.Email:
                services.Configure<EmailOptions>(configuration.GetSection("EmailService"));
                services.AddScoped<INotificationService, EmailNotificationService>();
                break;

            case NotificationServiceType.Ferre:
                services.AddScoped<INotificationService, FerreNotificationService>();
                break;

            case NotificationServiceType.None:
            default:
                services.AddScoped<INotificationService, NoneNotificationService>();
                break;
        }

        return services;
    }

    private static IServiceCollection AddAuthenticationService(this IServiceCollection services, IConfiguration configuration)
    {
        var loginService = configuration.RequiredEnum<SupportedLoginServicesEnum>("AuthService");
        switch (loginService)
        {
            case SupportedLoginServicesEnum.Full:
                services.AddScoped<IAuthService, FullAuthService>();
                break;

            case SupportedLoginServicesEnum.Bypass:
                services.AddScoped<IAuthService, BypassAuthService>();
                break;

            case SupportedLoginServicesEnum.Nemo:
                services.AddDbContext<NemoAccountContext>(options =>
                {
                    options.UseSqlServer(configuration.RequiredString("DbConfig:AccountDB"));
                    options.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
                });
                services.AddScoped<IAuthService, NemoAuthService>();
                break;

            case SupportedLoginServicesEnum.Simple:
            default:
                services.AddScoped<IAuthService, SimpleAuthService>();
                break;
        }

        return services;
    }
}
