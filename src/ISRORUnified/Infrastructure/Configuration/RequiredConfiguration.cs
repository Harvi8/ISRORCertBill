namespace ISRORUnified.Infrastructure.Configuration;

internal static class RequiredConfiguration
{
    public static string RequiredString(this IConfiguration configuration, string key)
    {
        var value = configuration[key];
        if (string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException($"Missing required configuration value: {key}");

        return value;
    }

    public static int RequiredInt(this IConfiguration configuration, string key)
    {
        var value = configuration.RequiredString(key);
        if (!int.TryParse(value, out var parsed))
            throw new InvalidOperationException($"Configuration value {key} must be an integer.");

        return parsed;
    }

    public static bool RequiredBool(this IConfiguration configuration, string key)
    {
        var value = configuration.RequiredString(key);
        if (!bool.TryParse(value, out var parsed))
            throw new InvalidOperationException($"Configuration value {key} must be true or false.");

        return parsed;
    }

    public static TEnum RequiredEnum<TEnum>(this IConfiguration configuration, string key)
        where TEnum : struct, Enum
    {
        var value = configuration.RequiredString(key);
        if (!Enum.TryParse<TEnum>(value, true, out var parsed))
            throw new InvalidOperationException(
                $"Configuration value {key} must be one of: {string.Join(", ", Enum.GetNames<TEnum>())}.");

        return parsed;
    }
}
