---
document type: cmdlet
external help file: DnsResolver.dll-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DnsResolver
ms.date: 09-28-2026
PlatyPS schema version: 2024-05-01
title: Resolve-DnsRecord
---

# Resolve-DnsRecord

## SYNOPSIS

Resolves DNS records for one or more names using the cross-platform .NET DNS resolver.

## SYNTAX

### __AllParameterSets

```
Resolve-DnsRecord [-Name] <string[]> [[-Type] <DnsRecordType[]>] [-Server <string[]>]
 [-TimeoutSec <int>] [-ThrottleLimit <int>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases:

- `Resolve-Dns`

## DESCRIPTION

The `Resolve-DnsRecord` cmdlet queries DNS servers for records of the requested types by using
`System.Net.DnsResolver`, which is available in .NET 11 on Windows, Linux, and macOS.

When `-Type` is omitted, the cmdlet queries A and AAAA records. When the name is an IP address, it
performs a reverse (PTR) lookup instead.

Each record is returned as a typed object that derives from `DnsResolver.DnsRecord` and exposes
`Name`, `Type`, `Ttl`, and `Data`, plus properties specific to the record type.

DNS failures such as NXDOMAIN or SERVFAIL are written as non-terminating errors. The exception is
a `DnsResolver.DnsResponseException` whose `ResponseCode` property contains the DNS response code.
An NXDOMAIN response is reported once per name, even when several record types were requested.

Queries for all names and record types run concurrently, up to `-ThrottleLimit` at a time.
Results are written in input order.

## EXAMPLES

### Example 1: Resolve the addresses of a host

```powershell
Resolve-DnsRecord -Name github.com
```

```Output
Name       Type TTL Data
----       ---- --- ----
github.com A     60 140.82.121.3
```

Queries A and AAAA records with the system-configured DNS servers.

### Example 2: Query several record types against a specific server

```powershell
Resolve-DnsRecord -Name google.com -Type MX, NS, TXT -Server 1.1.1.1
```

Queries MX, NS, and TXT records from Cloudflare's public resolver.

### Example 3: Query all record types for a name

```powershell
Resolve-DnsRecord -Name google.com -Type All
```

Queries A, AAAA, CNAME, MX, NS, and TXT records concurrently and returns every record found.

### Example 4: Perform a reverse lookup

```powershell
Resolve-DnsRecord -Name 1.1.1.1
```

```Output
Name    Type  TTL Data
----    ----  --- ----
1.1.1.1 PTR  1800 one.one.one.one
```

An IP address is resolved with a PTR query when `-Type` is not specified.

### Example 5: Resolve names from the pipeline and use typed properties

```powershell
'contoso.com', 'fabrikam.com' | Resolve-DnsRecord -Type MX |
    Sort-Object Preference |
    Select-Object Name, Preference, Exchange
```

MX records expose `Exchange` and `Preference` properties that can be sorted and selected.

### Example 6: Find the endpoints of a service

```powershell
Resolve-DnsRecord -Name _ldap._tcp.contoso.com -Type SRV | Select-Object Target, Port, Priority, Weight
```

SRV records expose `Target`, `Port`, `Priority`, `Weight`, and `Addresses`.

### Example 7: Handle a nonexistent name

```powershell
Resolve-DnsRecord -Name does-not-exist.invalid -ErrorAction SilentlyContinue -ErrorVariable dnsError
$dnsError[0].Exception.ResponseCode
```

```Output
NxDomain
```

## PARAMETERS

### -Name

The DNS names to resolve. When a value is an IP address and `-Type` is not specified, a reverse
(PTR) lookup is performed.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- HostName
- ComputerName
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Server

The DNS servers to query instead of the system-configured servers. Accepts an IP address
(`1.1.1.1`), an IP address and port (`1.1.1.1:53`, `[2606:4700::1111]:53`), or a host name
(`dns.google`), which is resolved with the system resolver. The default port is 53.

On Windows, only port 53 is supported. Specifying another port causes a terminating error.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ThrottleLimit

The maximum number of DNS queries that run at the same time, from 1 to 256. The default is 16.
Queries for all names and record types run concurrently, but results are always written in input
order.

```yaml
Type: System.Int32
DefaultValue: 16
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeoutSec

The maximum time, in seconds, to wait for each query, from 1 to 3600. A query that times out writes
a non-terminating `System.TimeoutException` error. By default, the resolver's own timeout applies.

```yaml
Type: System.Int32
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Type

The record types to query. When omitted, A and AAAA records are queried, or PTR when the name is
an IP address. When both A and AAAA are specified, they are resolved in a single query.

`All` queries every applicable type concurrently: A, AAAA, CNAME, MX, NS, and TXT, plus SRV for
service names that start with an underscore, or only PTR for IP addresses and `.arpa` names. It
can be combined with other types.

```yaml
Type: DnsResolver.DnsRecordType[]
DefaultValue: A, AAAA
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues:
- A
- AAAA
- CNAME
- MX
- NS
- PTR
- SRV
- TXT
- All
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String

You can pipe DNS names to this cmdlet.

### System.String[]

You can pipe objects that have a `Name`, `HostName`, or `ComputerName` property.

## OUTPUTS

### DnsResolver.DnsRecord

The base type of all records. The actual type depends on the record:

- `DnsResolver.AddressRecord` (A, AAAA): `IPAddress`
- `DnsResolver.CNameRecord`: `CanonicalName`
- `DnsResolver.MxRecord`: `Exchange`, `Preference`
- `DnsResolver.NsRecord`: `NameServer`
- `DnsResolver.PtrRecord`: `HostName`
- `DnsResolver.SrvRecord`: `Target`, `Port`, `Priority`, `Weight`, `Addresses`
- `DnsResolver.TxtRecord`: `Values`, `Text`

## NOTES

Requires PowerShell 7.7 or later running on .NET 11.

Press Ctrl+C to cancel a query in progress.

## RELATED LINKS

- [Test-DnsRecord](Test-DnsRecord.md)
