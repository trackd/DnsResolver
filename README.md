# DnsResolver

Cross-platform DNS lookups for PowerShell, built on the new managed [`System.Net.DnsResolver`](https://learn.microsoft.com/en-us/dotnet/api/system.net.dnsresolver?view=net-11.0).  
introduced in .NET 11, supported on Windows, Linux, and macOS

```powershell
PS> Resolve-DnsRecord github.com, 1.1.1.1

Name       Type  TTL Data
----       ----  --- ----
github.com A      60 140.82.121.3
1.1.1.1    PTR  1800 one.one.one.one
```

## Features

- Query A, AAAA, CNAME, MX, NS, PTR, SRV, and TXT records, or `-Type All` for every supported type.
- Automatic reverse (PTR) lookups when the name is an IP address.
- Concurrent queries with ordered output, limited by `-ThrottleLimit`.
- Custom DNS servers by IP address, IP and port, or host name.
- Per-query timeouts with `-TimeoutSec`, and Ctrl+C cancels queries in flight.
- Typed result objects, such as `MxRecord.Exchange` and `SrvRecord.Port`, that work naturally in the
  pipeline.
- DNS failures such as NXDOMAIN and SERVFAIL surface as regular PowerShell errors that expose the
  response code.

## Install

```powershell
Install-Module DnsResolver
```

## Requirements

- PowerShell 7.7 (probably preview-5 or later), running on .NET 11 rc1

## Build

```powershell
git clone <repository-url>
cd DnsResolver
./build.ps1
Import-Module ./output/DnsResolver.psd1
```

## Cmdlets

| Cmdlet | Alias | Description |
| --- | --- | --- |
| [`Resolve-DnsRecord`](docs/en-US/DnsResolver/Resolve-DnsRecord.md) | `Resolve-Dns` | Resolves DNS records for one or more names. |
| [`Test-DnsRecord`](docs/en-US/DnsResolver/Test-DnsRecord.md) | `Test-Dns` | Returns `$true` or `$false` depending on whether each name resolves. |

Full help is available with `Get-Help <cmdlet> -Full` after importing the module.

## Examples

Query specific record types against a specific server:

```powershell
Resolve-DnsRecord google.com -Type MX, TXT -Server 1.1.1.1
```

Get every supported record type that exists for a name:

```powershell
Resolve-DnsRecord cloudflare.com -Type All
```

Use the typed properties of the results:

```powershell
Resolve-DnsRecord contoso.com -Type MX | Sort-Object Preference | Select-Object -First 1 -ExpandProperty Exchange
Resolve-DnsRecord _ldap._tcp.contoso.com -Type SRV | Select-Object Target, Port, Priority, Weight
```

Resolve many names concurrently:

```powershell
Get-Content hosts.txt | Resolve-DnsRecord -ThrottleLimit 32 -TimeoutSec 5
```

Test whether names resolve:

```powershell
'github.com', 'does-not-exist.invalid' | Test-DnsRecord
```

Inspect a failed lookup:

```powershell
Resolve-DnsRecord does-not-exist.invalid -ErrorAction SilentlyContinue -ErrorVariable dnsError
$dnsError[0].Exception.ResponseCode   # NxDomain
```

## Output types

Every record derives from `DnsResolver.DnsRecord`, which exposes `Name`, `Type`, `Ttl`, and `Data`.
Converting a record to a string returns `Data`.

| Type | Record types | Additional properties |
| --- | --- | --- |
| `DnsResolver.AddressRecord` | A, AAAA | `IPAddress` |
| `DnsResolver.CNameRecord` | CNAME | `CanonicalName` |
| `DnsResolver.MxRecord` | MX | `Exchange`, `Preference` |
| `DnsResolver.NsRecord` | NS | `NameServer` |
| `DnsResolver.PtrRecord` | PTR | `HostName` |
| `DnsResolver.SrvRecord` | SRV | `Target`, `Port`, `Priority`, `Weight`, `Addresses` |
| `DnsResolver.TxtRecord` | TXT | `Values`, `Text` |

## Known limitations

- On Windows, `System.Net.DnsResolver` supports only port 53 for custom servers. Other ports cause a
  terminating error.
- `System.Net.DnsResolver` does not expose retry, TCP, or DNSSEC options.
- DNS ANY queries are not used, because they are deprecated by RFC 8482. `-Type All` sends one query
  per record type instead.

## Development

The build uses [InvokeBuild](https://github.com/nightroman/Invoke-Build),
[Microsoft.PowerShell.PlatyPS](https://github.com/PowerShell/platyPS) for help, and
[Pester](https://github.com/pester/Pester) 6 for tests. `build.ps1` installs InvokeBuild and PlatyPS
if they are missing.

```powershell
./build.ps1                 # clean, build, generate help, run tests
./build.ps1 -SkipHelp       # skip help generation
./build.ps1 -SkipTests      # skip tests
```

| Path | Contents |
| --- | --- |
| `src/DnsResolver/` | C# source for the binary module |
| `module/` | Module manifest and format file |
| `docs/en-US/` | PlatyPS markdown help, compiled to MAML during the build |
| `tests/` | Pester tests (tags: `Unit`, `Integration`, `Help`) |
| `output/` | Build output (not committed) |

Integration tests query public DNS servers such as `1.1.1.1` and are skipped automatically when they
are unreachable. To run only the offline tests:

```powershell
Invoke-Pester ./tests -ExcludeTag Integration
```
