using System;
using System.Linq;

namespace ISRORCert
{
    internal class CertificationConfig
    {
        public string DbConfig { get; set; } = default!;
        public string Serializer { get; set; } = default!;
        public int TickIntervalMs { get; set; }
        public string ListenAddressOverride { get; set; } = default!;
        public int ListenPortOverride { get; set; }
    }
}
