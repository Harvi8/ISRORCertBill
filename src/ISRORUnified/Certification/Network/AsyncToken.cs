using System.Net.Sockets;

namespace ISRORCert.Network
{
    public class AsyncToken
    {
        public Socket Socket { get; set; } = null!;
        public IAsyncInterface Interface { get; set; } = null!;
    }
}
