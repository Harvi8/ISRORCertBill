using ISRORCert.Database;
using ISRORCert.Model;
using ISRORCert.Network;

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;


namespace ISRORCert.Services
{
    internal class CertificationService : IHostedService
    {
        private readonly ILogger _logger;

        private readonly IOptions<CertificationConfig> _options;
        private readonly AsyncServer _server;
        private readonly IAsyncInterface _serverInterface;
        private readonly CertificationManager _certificationManager;
        private readonly IDbAdapter _adapter;

        public CertificationService(ILogger<CertificationService> logger,
                                    IOptions<CertificationConfig> options,
                                    IAsyncInterface serverInterface,
                                    AsyncServer server,
                                    CertificationManager certificationManager,
                                    IDbAdapter adapter)
        {
            _logger = logger;
            _options = options;
            _serverInterface = serverInterface;
            _server = server;
            _certificationManager = certificationManager;
            _adapter = adapter;
        }

        public async Task StartAsync(CancellationToken cancellationToken)
        {
            _adapter.ConnectionString = _options.Value.DbConfig;
            if (!await _certificationManager.RefreshAsync(cancellationToken))
                return;

            CreateListener();
        }

        private void CreateListener()
        {
            ArgumentNullException.ThrowIfNull(_certificationManager.Identity?.Machine);

            var databaseHost = _certificationManager.Identity.Machine.PublicIP;
            var databasePort = _certificationManager.Identity.ListenerPort;
            var host = string.IsNullOrWhiteSpace(_options.Value.ListenAddressOverride)
                ? databaseHost
                : _options.Value.ListenAddressOverride;
            var port = _options.Value.ListenPortOverride > 0
                ? _options.Value.ListenPortOverride
                : databasePort;

            _server.Accept(host, port, 128, _serverInterface);
            _logger.LogInformation(
                "Listening on {host}:{port} (database endpoint {databaseHost}:{databasePort})",
                host,
                port,
                databaseHost,
                databasePort);
        }

        public Task StopAsync(CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }
}
