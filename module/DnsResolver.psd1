@{
    RootModule           = 'DnsResolver.dll'
    ModuleVersion        = '0.1'
    CompatiblePSEditions = @('Core')
    GUID                 = 'c3b79fa8-d666-41d3-8c46-5ba868cf9681'
    Author               = 'trackd'
    CompanyName          = 'trackd'
    Copyright            = '(c) trackd. All rights reserved.'
    Description          = 'Cross-platform DNS resolving cmdlets built on System.Net.DnsResolver (.NET 11).
                            Requires 7.7-preview5 or later to work.'
    PowerShellVersion    = '7.7'
    FormatsToProcess     = @('DnsResolver.format.ps1xml')
    FunctionsToExport    = @()
    CmdletsToExport      = @('Resolve-DnsRecord', 'Test-DnsRecord')
    VariablesToExport    = @()
    AliasesToExport      = @('Resolve-Dns', 'Test-Dns')
    PrivateData          = @{
        PSData = @{
            Tags       = @('Windows', 'Linux', 'OSX', 'DNS')
            LicenseUri = 'https://github.com/trackd/DnsResolver/blob/main/LICENSE'
            ProjectUri = 'https://github.com/trackd/DnsResolver'
            # ReleaseNotes = ''
            # Prerelease = ''
        }
    }
}
