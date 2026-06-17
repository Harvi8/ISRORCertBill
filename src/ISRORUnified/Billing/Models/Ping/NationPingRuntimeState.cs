namespace ISRORBilling.Models.Ping;

public sealed class NationPingRuntimeState
{
    private readonly object _lock = new();
    private bool _running;
    private string? _error;

    public bool Running
    {
        get
        {
            lock (_lock)
                return _running;
        }
    }

    public string? Error
    {
        get
        {
            lock (_lock)
                return _error;
        }
    }

    public void MarkRunning()
    {
        lock (_lock)
        {
            _running = true;
            _error = null;
        }
    }

    public void MarkFaulted(string error)
    {
        lock (_lock)
        {
            _running = false;
            _error = error;
        }
    }

    public void MarkStopped()
    {
        lock (_lock)
        {
            _running = false;
        }
    }
}
