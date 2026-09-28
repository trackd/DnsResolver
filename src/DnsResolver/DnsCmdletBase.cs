using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using NetDnsResolver = System.Net.DnsResolver;

namespace DnsResolver;

public abstract class DnsCmdletBase : PSCmdlet, IDisposable {
    private const int DefaultDnsPort = 53;
    // Finished outcomes buffered behind a slow head query, as a multiple of ThrottleLimit.
    private const int PendingWindowFactor = 4;
    private protected static readonly DnsRecordType?[] PtrQuery = [DnsRecordType.PTR];
    private protected static readonly DnsRecordType?[] AddressQuery = [null];
    private readonly Queue<Task<DnsQueryOutcome>> _pending = new();
    private NetDnsResolver? _resolver;
    private SemaphoreSlim? _throttle;
    // Also cancelled on Dispose, which covers upstream stops (Select-Object -First) that leave PipelineStopToken untouched.
    private CancellationTokenSource? _stop;
    private int _group;

    /// <summary>DNS servers to query, e.g. 1.1.1.1, 1.1.1.1:53, [2606:4700::1111]:53 or dns.google.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string[]? Server { get; set; }

    [Parameter]
    [ValidateRange(1, 3600)]
    public int TimeoutSec { get; set; }

    [Parameter]
    [ValidateRange(1, 256)]
    public int ThrottleLimit { get; set; } = 16;

    protected NetDnsResolver Resolver => _resolver ?? throw new InvalidOperationException("Resolver not initialized.");

    /// <summary>True when verbose output would be shown; lets callers skip formatting messages.</summary>
    private protected bool VerboseEnabled { get; private set; }

    protected override void BeginProcessing() {
        VerboseEnabled = MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose)
            ? ((SwitchParameter)verbose).IsPresent
            : GetVariableValue("VerbosePreference") is ActionPreference pref
                && pref is not (ActionPreference.SilentlyContinue or ActionPreference.Ignore);
        _stop = CancellationTokenSource.CreateLinkedTokenSource(PipelineStopToken);
        _throttle = new SemaphoreSlim(ThrottleLimit, ThrottleLimit);
        if (Server is not { Length: > 0 }) {
            _resolver = new NetDnsResolver();
            return;
        }

        var servers = new List<IPEndPoint>();
        foreach (string s in Server) {
            servers.AddRange(ParseServer(s));
        }
        WriteVerbose($"Using DNS servers: {string.Join(", ", servers)}");
        try {
            _resolver = new NetDnsResolver(new DnsResolverOptions { Servers = servers });
        }
        catch (PlatformNotSupportedException ex) {
            ThrowTerminatingError(new ErrorRecord(ex, "UnsupportedServer", ErrorCategory.InvalidArgument, Server));
        }
    }

    protected override void EndProcessing() => Drain(maxPending: 0);

    public void Dispose() {
        _stop?.Cancel();
        _stop?.Dispose();
        _resolver?.Dispose();
        _throttle?.Dispose();
        GC.SuppressFinalize(this);
    }

    private IPEndPoint[] ParseServer(string server) {
        if (IPEndPoint.TryParse(server, out IPEndPoint? endpoint)) {
            if (endpoint.Port == 0) {
                endpoint.Port = DefaultDnsPort;
            }
            return [endpoint];
        }

        try {
            IPAddress[] addresses = Dns.GetHostAddressesAsync(server, PipelineStopToken).GetAwaiter().GetResult();
            return [.. addresses.Select(a => new IPEndPoint(a, DefaultDnsPort))];
        }
        catch (OperationCanceledException) {
            throw new PipelineStoppedException();
        }
        catch (SocketException ex) {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException($"Unable to resolve DNS server '{server}': {ex.Message}", nameof(server), ex),
                "InvalidServer", ErrorCategory.InvalidArgument, server));
            return [];
        }
    }

    /// <summary>Called on the pipeline thread for each finished query, in the order the queries were queued.</summary>
    private protected abstract void WriteOutcome(DnsQueryOutcome outcome);

    /// <summary>Starts queries for one name; a null type queries both A and AAAA.</summary>
    private protected void Enqueue(string name, DnsRecordType?[] types) {
        int group = _group++;
        foreach (DnsRecordType? type in types) {
            _pending.Enqueue(QueryAsync(group, name, type));
        }
        Drain(ThrottleLimit * PendingWindowFactor);
    }

    /// <summary>Writes finished outcomes in order, blocking while more than <paramref name="maxPending"/> are queued.</summary>
    private void Drain(int maxPending) {
        while (_pending.TryPeek(out Task<DnsQueryOutcome>? next)) {
            if (!next.IsCompleted) {
                if (_pending.Count <= maxPending) {
                    return;
                }
                try {
                    next.Wait(PipelineStopToken);
                }
                catch (OperationCanceledException) {
                    throw new PipelineStoppedException();
                }
            }

            _pending.Dequeue();
            DnsQueryOutcome outcome = next.Result;
            if (outcome.Error is OperationCanceledException && PipelineStopToken.IsCancellationRequested) {
                throw new PipelineStoppedException();
            }
            WriteOutcome(outcome);
        }
    }

    // Never faults: failures are returned in the outcome so they can be written in order.
    private async Task<DnsQueryOutcome> QueryAsync(int group, string name, DnsRecordType? type) {
        CancellationToken stop = _stop!.Token;
        try {
            await _throttle!.WaitAsync(stop).ConfigureAwait(false);
            CancellationTokenSource? timeout = null;
            try {
                CancellationToken ct = stop;
                if (TimeoutSec > 0) {
                    timeout = CancellationTokenSource.CreateLinkedTokenSource(stop);
                    timeout.CancelAfter(TimeSpan.FromSeconds(TimeoutSec));
                    ct = timeout.Token;
                }

                DnsQueryResult result = type switch {
                    null => Map(await Resolver.ResolveAddressesAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new AddressRecord(n, r)),
                    DnsRecordType.A => Map(await Resolver.ResolveAddressesAsync(name, AddressFamily.InterNetwork, ct).ConfigureAwait(false), name, static (n, r) => new AddressRecord(n, r)),
                    DnsRecordType.AAAA => Map(await Resolver.ResolveAddressesAsync(name, AddressFamily.InterNetworkV6, ct).ConfigureAwait(false), name, static (n, r) => new AddressRecord(n, r)),
                    DnsRecordType.CNAME => Map(await Resolver.ResolveCNameAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new CNameRecord(n, r)),
                    DnsRecordType.MX => Map(await Resolver.ResolveMxAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new MxRecord(n, r)),
                    DnsRecordType.NS => Map(await Resolver.ResolveNsAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new NsRecord(n, r)),
                    DnsRecordType.PTR => IPAddress.TryParse(name, out IPAddress? ip)
                        ? Map(await Resolver.ResolvePtrAsync(ip, ct).ConfigureAwait(false), name, static (n, r) => new PtrRecord(n, r))
                        : Map(await Resolver.ResolvePtrAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new PtrRecord(n, r)),
                    DnsRecordType.SRV => Map(await Resolver.ResolveSrvAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new SrvRecord(n, r)),
                    DnsRecordType.TXT => Map(await Resolver.ResolveTxtAsync(name, ct).ConfigureAwait(false), name, static (n, r) => new TxtRecord(n, r)),
                    _ => throw new ArgumentOutOfRangeException(nameof(type), type, null),
                };
                return new(group, name, type, result, null);
            }
            catch (OperationCanceledException ex) when (timeout is { IsCancellationRequested: true } && !stop.IsCancellationRequested) {
                return new(group, name, type, default, new TimeoutException($"DNS query timed out after {TimeoutSec} seconds.", ex));
            }
            finally {
                timeout?.Dispose();
                _throttle.Release();
            }
        }
        catch (Exception ex) {
            return new(group, name, type, default, ex);
        }
    }

    internal static bool IsIPAddress(string name) => IPAddress.TryParse(name, out _);

    private static DnsQueryResult Map<T>(DnsResult<T> result, string name, Func<string, T, DnsRecord> map) {
        IReadOnlyList<T>? records = result.Records;
        DnsRecord[] mapped = records is { Count: > 0 } ? new DnsRecord[records.Count] : [];
        for (int i = 0; i < mapped.Length; i++) {
            mapped[i] = map(name, records[i]);
        }
        return new(result.ResponseCode, result.NegativeCacheTtl, mapped);
    }

    internal static ErrorCategory GetErrorCategory(DnsResponseCode code) => code switch {
        DnsResponseCode.NxDomain => ErrorCategory.ObjectNotFound,
        DnsResponseCode.Refused => ErrorCategory.PermissionDenied,
        DnsResponseCode.ServerFailure => ErrorCategory.ResourceUnavailable,
        DnsResponseCode.FormatError => ErrorCategory.InvalidData,
        DnsResponseCode.NotImplemented => ErrorCategory.NotImplemented,
        _ => ErrorCategory.InvalidResult,
    };
}
