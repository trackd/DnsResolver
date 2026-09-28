using System;
using System.Management.Automation;
using System.Net;

namespace DnsResolver;

[Cmdlet(VerbsDiagnostic.Test, "DnsRecord")]
[Alias("Test-Dns")]
[OutputType(typeof(bool))]
public sealed class TestDnsRecordCommand : DnsCmdletBase {
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
    [Alias("HostName", "ComputerName")]
    [ValidateNotNullOrEmpty]
    public string[] Name { get; set; } = [];

    /// <summary>Record type to test for. Defaults to A or AAAA, or PTR when Name is an IP address.</summary>
    [Parameter(Position = 1)]
    public DnsRecordType? Type { get; set; }

    private DnsRecordType?[]? _queryTypes;

    protected override void BeginProcessing() {
        if (Type == DnsRecordType.All) {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Type 'All' is not supported by Test-DnsRecord; specify a single record type.", nameof(Type)),
                "AllNotSupported", ErrorCategory.InvalidArgument, Type));
        }
        _queryTypes = Type is null ? null : [Type];
        base.BeginProcessing();
    }

    protected override void ProcessRecord() {
        foreach (string name in Name) {
            Enqueue(name, _queryTypes ?? (IsIPAddress(name) ? PtrQuery : AddressQuery));
        }
    }

    private protected override void WriteOutcome(DnsQueryOutcome outcome) {
        (_, string name, DnsRecordType? type, DnsQueryResult result, Exception? error) = outcome;
        if (error is not null) {
            if (VerboseEnabled) {
                WriteVerbose($"'{name}': {error.Message}");
            }
            WriteObject(false);
            return;
        }

        if (VerboseEnabled) {
            WriteVerbose($"'{name}' ({type?.ToString() ?? "A/AAAA"}): {result.ResponseCode}, {result.Records.Length} record(s).");
        }
        WriteObject(result.ResponseCode == DnsResponseCode.NoError && result.Records.Length > 0);
    }
}
