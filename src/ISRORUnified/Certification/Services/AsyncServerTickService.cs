using ISRORCert.Network;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace ISRORCert.Services
{
    internal class AsyncServerTickService : BackgroundService
    {
        // This is not exact timing, but Certification is not under heavy duty.
        private readonly PeriodicTimer _timer;
        private readonly AsyncServer _serverInterface;

        public AsyncServerTickService(AsyncServer serverInterface, IOptions<CertificationConfig> options)
        {
            _serverInterface = serverInterface;
            var tickIntervalMs = Math.Max(1, options.Value.TickIntervalMs);
            _timer = new PeriodicTimer(TimeSpan.FromMilliseconds(tickIntervalMs));
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            while (await _timer.WaitForNextTickAsync(stoppingToken) && !stoppingToken.IsCancellationRequested)
                _serverInterface.Tick();
        }
    }
}
