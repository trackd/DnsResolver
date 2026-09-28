using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Net;

namespace DnsResolver;

[Cmdlet(VerbsDiagnostic.Resolve, "DnsRecord")]
[Alias("Resolve-Dns")]
[OutputType(typeof(DnsRecord))]
public sealed class ResolveDnsRecordCommand : DnsCmdletBase {
    [Parameter(
        Mandatory = true,
        Position = 0,
        ValueFromPipeline = true,
        ValueFromPipelineByPropertyName = true
    )]
    [Alias("HostName", "ComputerName")]
    [ValidateNotNullOrEmpty]
    public string[] Name { get; set; } = [];

    /// <summary>Record types to query. Defaults to A and AAAA, or PTR when Name is an IP address.</summary>
    [Parameter(Position = 1)]
    [ValidateNotNullOrEmpty]
    public DnsRecordType[]? Type { get; set; }

    private int _nxDomainGroup = -1;
    private bool _hasAll;
    // Query types depend on the name only through its kind when -Type includes All; indexed by NameKind.
    private readonly DnsRecordType?[]?[] _queryTypes = new DnsRecordType?[]?[3];

    private enum NameKind { Common, Reverse, Service }

    protected override void BeginProcessing() {
        _hasAll = Type is not null && Array.IndexOf(Type, DnsRecordType.All) >= 0;
        base.BeginProcessing();
    }

    protected override void ProcessRecord() {
        foreach (string name in Name) {
            Enqueue(name, GetQueryTypes(name));
        }
    }

    private protected override void WriteOutcome(DnsQueryOutcome outcome) {
        (int group, string name, DnsRecordType? type, DnsQueryResult result, Exception? error) = outcome;
        if (error is not null) {
            WriteError(new ErrorRecord(error, "DnsQueryFailed", ErrorCategory.ConnectionError, name));
            return;
        }

        if (result.ResponseCode != DnsResponseCode.NoError) {
            // A nonexistent name fails every record type; report it once per name.
            if (result.ResponseCode == DnsResponseCode.NxDomain) {
                if (_nxDomainGroup == group) {
                    return;
                }
                _nxDomainGroup = group;
            }

            WriteError(new ErrorRecord(
                new DnsResponseException(name, type, result.ResponseCode),
                $"Dns{result.ResponseCode}",
                GetErrorCategory(result.ResponseCode),
                name));
            return;
        }

        if (result.Records.Length == 0 && VerboseEnabled) {
            WriteVerbose($"No {type?.ToString() ?? "A/AAAA"} records for '{name}' (negative cache TTL {result.NegativeCacheTtl}).");
        }

        WriteObject(result.Records, enumerateCollection: true);
    }

    private DnsRecordType?[] GetQueryTypes(string name) {
        if (Type is null) {
            return IsIPAddress(name) ? PtrQuery : AddressQuery;
        }

        NameKind kind = _hasAll ? GetNameKind(name) : NameKind.Common;
        return _queryTypes[(int)kind] ??= BuildQueryTypes(Type, kind);
    }

    private static DnsRecordType?[] BuildQueryTypes(DnsRecordType[] requested, NameKind kind) {
        DnsRecordType[] types = [.. requested.SelectMany(t => t == DnsRecordType.All ? ExpandAll(kind) : [t]).Distinct()];
        bool combineAddresses = types.Contains(DnsRecordType.A) && types.Contains(DnsRecordType.AAAA);
        return !combineAddresses
            ? [.. types.Cast<DnsRecordType?>()]
            : [.. types
                .Where(t => t != DnsRecordType.AAAA)
                .Select(t => t == DnsRecordType.A ? null : (DnsRecordType?)t)];
    }

    private static NameKind GetNameKind(string name) {
        if (IsIPAddress(name) || name.AsSpan().TrimEnd('.').EndsWith(".arpa", StringComparison.OrdinalIgnoreCase)) {
            return NameKind.Reverse;
        }
        // Service names like _ldap._tcp.contoso.com are the only place SRV records live.
        return name.StartsWith('_') ? NameKind.Service : NameKind.Common;
    }

    private static DnsRecordType[] ExpandAll(NameKind kind) {
        if (kind == NameKind.Reverse) {
            return [DnsRecordType.PTR];
        }

        DnsRecordType[] common = [DnsRecordType.A, DnsRecordType.AAAA, DnsRecordType.CNAME, DnsRecordType.MX, DnsRecordType.NS, DnsRecordType.TXT];
        return kind == NameKind.Service ? [.. common, DnsRecordType.SRV] : common;
    }
}
