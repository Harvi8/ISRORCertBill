namespace ISRORBilling.Models.Ping;

public class NationPingServiceOptions
{
    public string ListenAddress { get; set; } = default!;
    public int ListenPort { get; set; }
}
