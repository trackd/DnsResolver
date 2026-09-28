using System;
using System.Linq;
using System.Net;
using System.Net.Sockets;

namespace DnsResolver;
#pragma warning disable CA1720
public enum DnsRecordType {
    A,
    AAAA,
    CNAME,
    MX,
    NS,
    PTR,
    SRV,
    TXT,
    // Expanded client-side into the applicable types; ANY queries are deprecated (RFC 8482).
    All,
}
#pragma warning restore CA1720
public sealed class DnsResponseException(string name, DnsRecordType? type, DnsResponseCode responseCode)
    : Exception($"DNS query for '{name}' ({type?.ToString() ?? "A/AAAA"}) failed: {responseCode}") {
    public string Name { get; } = name;
    public DnsRecordType? Type { get; } = type;
    public DnsResponseCode ResponseCode { get; } = responseCode;
}

public abstract class DnsRecord(string name, DnsRecordType type, TimeSpan ttl) {
    public string Name { get; } = name;
    public DnsRecordType Type { get; } = type;
    public TimeSpan Ttl { get; } = ttl;
    public abstract string Data { get; }
    public override string ToString() => Data;
}

// Record types intentionally share names with their System.Net counterparts, which they wrap.
public sealed class AddressRecord(string name, System.Net.AddressRecord record)
    : DnsRecord(name, record.Address.AddressFamily == AddressFamily.InterNetworkV6 ? DnsRecordType.AAAA : DnsRecordType.A, record.Ttl) {
    // Not named Address: $array.Address resolves to Array.Address(int) in PowerShell.
    public IPAddress IPAddress { get; } = record.Address;
    public override string Data => IPAddress.ToString();
}

public sealed class CNameRecord(string name, System.Net.CNameRecord record) : DnsRecord(name, DnsRecordType.CNAME, record.Ttl) {
    public string CanonicalName { get; } = record.CanonicalName;
    public override string Data => CanonicalName;
}

public sealed class MxRecord(string name, System.Net.MxRecord record) : DnsRecord(name, DnsRecordType.MX, record.Ttl) {
    public string Exchange { get; } = record.Exchange;
    public ushort Preference { get; } = record.Preference;
    public override string Data => $"{Preference} {Exchange}";
}

public sealed class NsRecord(string name, System.Net.NsRecord record) : DnsRecord(name, DnsRecordType.NS, record.Ttl) {
    public string NameServer { get; } = record.Name;
    public override string Data => NameServer;
}

public sealed class PtrRecord(string name, System.Net.PtrRecord record) : DnsRecord(name, DnsRecordType.PTR, record.Ttl) {
    public string HostName { get; } = record.Name;
    public override string Data => HostName;
}

public sealed class SrvRecord(string name, System.Net.SrvRecord record) : DnsRecord(name, DnsRecordType.SRV, record.Ttl) {
    public string Target { get; } = record.Target;
    public ushort Port { get; } = record.Port;
    public ushort Priority { get; } = record.Priority;
    public ushort Weight { get; } = record.Weight;
    public IPAddress[] Addresses { get; } = record.Addresses?.Select(a => a.Address).ToArray() ?? [];
    public override string Data => $"{Priority} {Weight} {Port} {Target}";
}

public sealed class TxtRecord(string name, System.Net.TxtRecord record) : DnsRecord(name, DnsRecordType.TXT, record.Ttl) {
    public string[] Values { get; } = record.Values?.ToArray() ?? [];
    public string Text => string.Concat(Values);
    public override string Data => Text;
}

internal readonly record struct DnsQueryResult(DnsResponseCode ResponseCode, TimeSpan NegativeCacheTtl, DnsRecord[] Records);

/// <summary>A finished query; <see cref="Group"/> identifies the input name it was queued for.</summary>
internal readonly record struct DnsQueryOutcome(int Group, string Name, DnsRecordType? Type, DnsQueryResult Result, Exception? Error);
