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

Describe 'Test-DnsRecord' -Tag 'Unit' {
    It 'Is exported with the alias Test-Dns' {
        (Get-Alias -Name Test-Dns).ResolvedCommand.Name | Should -Be 'Test-DnsRecord'
    }

    It 'Returns $false on timeout instead of writing an error' {
        $result = Test-DnsRecord -Name 'example.com' -Server $blackhole -TimeoutSec 1 -ErrorVariable err
        $result | Should -BeFalse
        $err | Should -BeNullOrEmpty
    }

    It 'Throws a terminating error for an unresolvable server host name' {
        { Test-DnsRecord -Name 'example.com' -Server 'no-such-server.invalid' } |
            Should -Throw -ErrorId 'InvalidServer,DnsResolver.TestDnsRecordCommand'
    }

    It 'Rejects Type All' {
        { Test-DnsRecord -Name 'example.com' -Type All } |
            Should -Throw -ErrorId 'AllNotSupported,DnsResolver.TestDnsRecordCommand'
    }
}

Describe 'Test-DnsRecord' -Tag 'Integration' -Skip:$offline {
    It 'Returns $true for an existing name' {
        Test-DnsRecord -Name 'one.one.one.one' -Server $server | Should -BeTrue
    }

    It 'Returns $false for a nonexistent name' {
        Test-DnsRecord -Name 'does-not-exist.invalid' -Server $server | Should -BeFalse
    }

    It 'Returns $false when the name has no records of the requested type' {
        Test-DnsRecord -Name 'one.one.one.one' -Type MX -Server $server | Should -BeFalse
    }

    It 'Returns $true for a PTR lookup of an IP address' {
        Test-DnsRecord -Name '1.1.1.1' -Server $server | Should -BeTrue
    }

    It 'Returns one boolean per piped name in order' {
        $result = 'one.one.one.one', 'does-not-exist.invalid', 'dns.google' | Test-DnsRecord -Server $server
        $result | Should -Be $true, $false, $true
    }
}
