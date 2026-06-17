using ISRORCert;
using ISRORCert.Database;
using ISRORCert.Logic;
using ISRORCert.Logic.Handler;
using ISRORCert.Model;
using ISRORCert.Model.Serialization;
using ISRORCert.Network;
using ISRORCert.Services;
using ISRORUnified.Infrastructure.Configuration;
using Microsoft.Extensions.Options;

namespace ISRORUnified.Infrastructure.ServiceRegistration;

internal static class CertificationRegistration
{
    public static IServiceCollection AddCertification(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<CertificationConfig>(configuration.GetSection("CertificationConfig"));

        if (!configuration.RequiredBool("Features:Certification"))
            return services;

        services.AddSingleton<IDbAdapter, SqlDbAdapter>();

        services.AddSingleton<CertificationSerializerOld>();
        services.AddSingleton<CertificationSerializerNew>();
        services.AddSingleton<ICertificationSerializer>(serviceProvider =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<CertificationConfig>>().Value;
            return options.Serializer.Equals("Old", StringComparison.OrdinalIgnoreCase)
                ? serviceProvider.GetRequiredService<CertificationSerializerOld>()
                : serviceProvider.GetRequiredService<CertificationSerializerNew>();
        });

        services.AddSingleton<AsyncServer>();
        services.AddSingleton<IAsyncInterface, CertificationInterface>();
        services.AddSingleton<CertificationManager>();

        services.AddSingleton<PacketHandlerManager>();
        services.AddSingleton<IPacketHandler, PacketHandlerSetupCord>();
        services.AddSingleton<IPacketHandler, PacketHandlerCertificate>();
        services.AddSingleton<IPacketHandler, PacketHandlerNotify>();
        services.AddSingleton<IPacketHandler, PacketHandlerRelay>();
        services.AddSingleton<IPacketHandler, PacketHandlerChangeShardData>();

        services.AddHostedService<CertificationService>();
        services.AddHostedService<AsyncServerTickService>();

        return services;
    }
}
