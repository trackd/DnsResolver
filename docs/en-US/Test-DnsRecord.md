---
document type: cmdlet
external help file: DnsResolver.dll-Help.xml
HelpUri: ''
Locale: en-US
Module Name: DnsResolver
ms.date: 09-28-2026
PlatyPS schema version: 2024-05-01
title: Test-DnsRecord
---

# Test-DnsRecord

## SYNOPSIS

Tests whether DNS names resolve to at least one record.

## SYNTAX

### __AllParameterSets

```
Test-DnsRecord [-Name] <string[]> [[-Type] <DnsRecordType>] [-Server <string[]>]
 [-TimeoutSec <int>] [-ThrottleLimit <int>] [<CommonParameters>]
```

## ALIASES

This cmdlet has the following aliases:

- `Test-Dns`

## DESCRIPTION

The `Test-DnsRecord` cmdlet returns `$true` for each name that resolves with a NOERROR response
and at least one record of the requested type, and `$false` otherwise.

DNS failures and timeouts return `$false` instead of writing errors. Use `-Verbose` to see the
response code or failure reason. An invalid `-Server` value still causes a terminating error.

## EXAMPLES

### Example 1: Test whether a host name resolves

```powershell
Test-DnsRecord -Name github.com
```

```Output
True
```

### Example 2: Test several names from the pipeline

```powershell
'github.com', 'does-not-exist.invalid' | Test-DnsRecord
```

```Output
True
False
```

One Boolean is returned per name, in input order.

### Example 3: Test whether a domain accepts mail

```powershell
if (Test-DnsRecord -Name contoso.com -Type MX -Server 1.1.1.1 -TimeoutSec 5) {
    'contoso.com has MX records'
}
```

## PARAMETERS

### -Name

The DNS names to test. When a value is an IP address and `-Type` is not specified, a reverse
(PTR) lookup is tested.

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
Names are tested concurrently, but results are always written in input order.

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

The maximum time, in seconds, to wait for each query, from 1 to 3600. A query that times out
returns `$false`. By default, the resolver's own timeout applies.

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

The record type to test for. When omitted, the name passes if it has either an A or AAAA record,
or a PTR record when the name is an IP address.

```yaml
Type: System.Nullable`1[DnsResolver.DnsRecordType]
DefaultValue: ''
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

### System.Boolean

One value per input name: `$true` if the name resolved to at least one record, otherwise `$false`.

## NOTES

Requires PowerShell 7.7 or later running on .NET 11.

## RELATED LINKS

- [Resolve-DnsRecord](Resolve-DnsRecord.md)
