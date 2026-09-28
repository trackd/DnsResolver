BeforeDiscovery {
    if (-not (Get-Module -Name DnsResolver)) {
        Import-Module (Join-Path $PSScriptRoot '..' 'output' 'DnsResolver.psd1') -ErrorAction Stop
    }
    $offline = -not (Test-DnsRecord -Name 'one.one.one.one' -Server '1.1.1.1' -TimeoutSec 3)
}

BeforeAll {
    if (-not (Get-Module -Name DnsResolver)) {
        Import-Module (Join-Path $PSScriptRoot '..' 'output' 'DnsResolver.psd1') -ErrorAction Stop
    }
    $script:server = '1.1.1.1'
    # TEST-NET-1 (RFC 5737) is never routed, so queries to it always time out.
    $script:blackhole = '192.0.2.1'
}

Describe 'Resolve-DnsRecord' -Tag 'Unit' {
    Context 'Parameters' {
        BeforeAll {
            $command = Get-Command -Name Resolve-DnsRecord
        }

        It 'Has mandatory Name parameter accepting pipeline input' {
            $name = $command.Parameters['Name']
            $name.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
            $name.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -BeTrue
        }

        It 'Has alias <_> for Name' -ForEach 'HostName', 'ComputerName' {
            $command.Parameters['Name'].Aliases | Should -Contain $_
        }

        It 'Is exported with the alias Resolve-Dns' {
            (Get-Alias -Name Resolve-Dns).ResolvedCommand.Name | Should -Be 'Resolve-DnsRecord'
        }

        It 'Accepts record type <_>' -ForEach 'A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT', 'All' {
            [DnsResolver.DnsRecordType]$_ | Should -BeOfType [DnsResolver.DnsRecordType]
        }

        It 'Rejects an unknown record type' {
            { Resolve-DnsRecord -Name 'example.com' -Type 'BOGUS' } | Should -Throw -ErrorId 'CannotConvertArgumentNoMessage,DnsResolver.ResolveDnsRecordCommand'
        }

        It 'Rejects TimeoutSec <_>' -ForEach 0, 3601 {
            { Resolve-DnsRecord -Name 'example.com' -TimeoutSec $_ } | Should -Throw -ErrorId 'ParameterArgumentValidationError,DnsResolver.ResolveDnsRecordCommand'
        }

        It 'Rejects an empty Name' {
            { Resolve-DnsRecord -Name '' } | Should -Throw -ErrorId 'ParameterArgumentValidationError,DnsResolver.ResolveDnsRecordCommand'
        }
    }

    Context 'Server parsing' {
        It 'Throws a terminating error for an unresolvable server host name' {
            { Resolve-DnsRecord -Name 'example.com' -Server 'no-such-server.invalid' } |
                Should -Throw -ErrorId 'InvalidServer,DnsResolver.ResolveDnsRecordCommand'
        }

        It 'Accepts server format <_>' -ForEach '192.0.2.1', '192.0.2.1:53', '[2001:db8::1]:53' {
            { Resolve-DnsRecord -Name 'example.com' -Server $_ -TimeoutSec 1 -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Rejects a custom server port on Windows' -Skip:(-not $IsWindows) {
            { Resolve-DnsRecord -Name 'example.com' -Server '192.0.2.1:5353' } |
                Should -Throw -ErrorId 'UnsupportedServer,DnsResolver.ResolveDnsRecordCommand'
        }

        It 'Accepts a custom server port on non-Windows platforms' -Skip:$IsWindows {
            { Resolve-DnsRecord -Name 'example.com' -Server '192.0.2.1:5353' -TimeoutSec 1 -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context 'Timeout' {
        It 'Writes a non-terminating timeout error' {
            $result = Resolve-DnsRecord -Name 'example.com' -Server $blackhole -TimeoutSec 1 -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -HaveCount 1
            $err[0].Exception | Should -BeOfType [System.TimeoutException]
            $err[0].FullyQualifiedErrorId | Should -BeLike 'DnsQueryFailed,*'
        }

        It 'Continues with the next name after a timeout' {
            $null = Resolve-DnsRecord -Name 'a.example', 'b.example' -Server $blackhole -TimeoutSec 1 -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -HaveCount 2
        }
    }

    Context 'Concurrency' {
        It 'Rejects ThrottleLimit <_>' -ForEach 0, 257 {
            { Resolve-DnsRecord -Name 'example.com' -ThrottleLimit $_ } | Should -Throw -ErrorId 'ParameterArgumentValidationError,DnsResolver.ResolveDnsRecordCommand'
        }

        It 'Runs queries concurrently' {
            # Four 1-second timeouts would take about 4 seconds if run one at a time.
            $elapsed = Measure-Command {
                'a.example', 'b.example', 'c.example', 'd.example' |
                    Resolve-DnsRecord -Server $blackhole -TimeoutSec 1 -ErrorAction SilentlyContinue
            }
            $elapsed.TotalSeconds | Should -BeLessThan 2.5
        }

        It 'Honors ThrottleLimit 1 by running queries one at a time' {
            $elapsed = Measure-Command {
                'a.example', 'b.example' |
                    Resolve-DnsRecord -Server $blackhole -TimeoutSec 1 -ThrottleLimit 1 -ErrorAction SilentlyContinue
            }
            $elapsed.TotalSeconds | Should -BeGreaterOrEqual 1.9
        }

        It 'Writes errors in input order' {
            $null = 'a.example', 'b.example', 'c.example' |
                Resolve-DnsRecord -Server $blackhole -TimeoutSec 1 -ErrorVariable err -ErrorAction SilentlyContinue
            $err.TargetObject | Should -Be 'a.example', 'b.example', 'c.example'
        }
    }
}

Describe 'Resolve-DnsRecord' -Tag 'Integration' -Skip:$offline {
    Context 'Address records' {
        It 'Returns A and AAAA records by default' {
            $result = Resolve-DnsRecord -Name 'one.one.one.one' -Server $server
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType [DnsResolver.AddressRecord]
            $result.Type | Should -Contain ([DnsResolver.DnsRecordType]::A)
            $result.Type | Should -Contain ([DnsResolver.DnsRecordType]::AAAA)
            $result.IPAddress.IPAddressToString | Should -Contain '1.1.1.1'
        }

        It 'Returns only A records for -Type A' {
            $result = Resolve-DnsRecord -Name 'one.one.one.one' -Type A -Server $server
            $result.Type | Should -Not -Contain ([DnsResolver.DnsRecordType]::AAAA)
            $result.IPAddress.AddressFamily | Sort-Object -Unique | Should -Be 'InterNetwork'
        }

        It 'Returns only AAAA records for -Type AAAA' {
            $result = Resolve-DnsRecord -Name 'one.one.one.one' -Type AAAA -Server $server
            $result.IPAddress.AddressFamily | Sort-Object -Unique | Should -Be 'InterNetworkV6'
        }

        It 'Sets Name, Ttl and Data on each record' {
            $record = Resolve-DnsRecord -Name 'one.one.one.one' -Type A -Server $server | Select-Object -First 1
            $record.Name | Should -Be 'one.one.one.one'
            $record.Ttl | Should -BeOfType [timespan]
            $record.Data | Should -Be $record.IPAddress.ToString()
            "$record" | Should -Be $record.Data
        }

        It 'Accepts names from the pipeline' {
            $result = 'one.one.one.one', 'dns.google' | Resolve-DnsRecord -Type A -Server $server
            $result.Name | Sort-Object -Unique | Should -Be 'dns.google', 'one.one.one.one'
        }

        It 'Accepts names by property name via alias' {
            $result = [pscustomobject]@{ HostName = 'one.one.one.one' } | Resolve-DnsRecord -Type A -Server $server
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Other record types' {
        It 'Returns PTR records when Name is an IP address' {
            $result = Resolve-DnsRecord -Name '1.1.1.1' -Server $server
            $result[0] | Should -BeOfType [DnsResolver.PtrRecord]
            $result.HostName | Should -Contain 'one.one.one.one'
        }

        It 'Returns MX records' {
            $result = Resolve-DnsRecord -Name 'google.com' -Type MX -Server $server
            $result[0] | Should -BeOfType [DnsResolver.MxRecord]
            $result[0].Exchange | Should -Not -BeNullOrEmpty
            $result[0].Data | Should -Be "$($result[0].Preference) $($result[0].Exchange)"
        }

        It 'Returns NS records' {
            $result = Resolve-DnsRecord -Name 'google.com' -Type NS -Server $server
            $result.NameServer | Should -Contain 'ns1.google.com'
        }

        It 'Returns TXT records' {
            $result = Resolve-DnsRecord -Name 'google.com' -Type TXT -Server $server
            $result.Text | Should -Contain 'v=spf1 include:_spf.google.com ~all'
        }

        It 'Returns SRV records' {
            $result = Resolve-DnsRecord -Name '_ldap._tcp.google.com' -Type SRV -Server $server
            $result[0] | Should -BeOfType [DnsResolver.SrvRecord]
            $result[0].Port | Should -Be 389
        }

        It 'Returns CNAME records' {
            $result = Resolve-DnsRecord -Name 'www.microsoft.com' -Type CNAME -Server $server
            $result[0] | Should -BeOfType [DnsResolver.CNameRecord]
            $result[0].CanonicalName | Should -Not -BeNullOrEmpty
        }

        It 'Returns records for multiple types in one call' {
            $result = Resolve-DnsRecord -Name 'google.com' -Type MX, NS -Server $server
            $result.Type | Sort-Object -Unique | Should -Be ([DnsResolver.DnsRecordType]::MX), ([DnsResolver.DnsRecordType]::NS)
        }
    }

    Context 'Type All' {
        It 'Returns records of every type that exists for a host name' {
            $types = (Resolve-DnsRecord -Name 'google.com' -Type All -Server $server).Type
            $types | Should -Contain ([DnsResolver.DnsRecordType]::A)
            $types | Should -Contain ([DnsResolver.DnsRecordType]::AAAA)
            $types | Should -Contain ([DnsResolver.DnsRecordType]::MX)
            $types | Should -Contain ([DnsResolver.DnsRecordType]::NS)
            $types | Should -Contain ([DnsResolver.DnsRecordType]::TXT)
        }

        It 'Includes SRV for service names' {
            $result = Resolve-DnsRecord -Name '_ldap._tcp.google.com' -Type All -Server $server
            $result.Type | Should -Contain ([DnsResolver.DnsRecordType]::SRV)
        }

        It 'Queries only PTR for an IP address' {
            $result = Resolve-DnsRecord -Name '1.1.1.1' -Type All -Server $server
            $result.Type | Sort-Object -Unique | Should -Be ([DnsResolver.DnsRecordType]::PTR)
        }

        It 'Writes no errors for record types that do not exist' {
            $null = Resolve-DnsRecord -Name 'one.one.one.one' -Type All -Server $server -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -BeNullOrEmpty
        }

        It 'Reports NxDomain once for a nonexistent name' {
            $null = Resolve-DnsRecord -Name 'does-not-exist.invalid' -Type All -Server $server -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -HaveCount 1
        }
    }

    Context 'Failed lookups' {
        It 'Writes an NxDomain error for a nonexistent name' {
            $result = Resolve-DnsRecord -Name 'does-not-exist.invalid' -Server $server -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -HaveCount 1
            $err[0].Exception | Should -BeOfType [DnsResolver.DnsResponseException]
            $err[0].Exception.ResponseCode | Should -Be ([System.Net.DnsResponseCode]::NxDomain)
            $err[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $err[0].FullyQualifiedErrorId | Should -BeLike 'DnsNxDomain,*'
        }

        It 'Reports NxDomain once per name across record types' {
            $null = Resolve-DnsRecord -Name 'does-not-exist.invalid' -Type A, MX, TXT -Server $server -ErrorVariable err -ErrorAction SilentlyContinue
            $err | Should -HaveCount 1
        }

        It 'Returns nothing without error when the name has no records of the type' {
            $result = Resolve-DnsRecord -Name 'one.one.one.one' -Type MX -Server $server -ErrorVariable err -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $err | Should -BeNullOrEmpty
        }
    }
}
