namespace ISRORUnified.Infrastructure.ServiceRegistration;

internal static class LoggingRegistration
{
    public static IServiceCollection AddUnifiedLogging(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddLogging(loggingBuilder =>
        {
            var loggingSection = configuration.GetSection("Logging");
            loggingBuilder.ClearProviders();
            loggingBuilder.AddConfiguration(loggingSection);
            loggingBuilder.AddConsole();
            loggingBuilder.AddFile(loggingSection);
        });

        return services;
    }
}
