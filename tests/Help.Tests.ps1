BeforeDiscovery {
    if (-not (Get-Module -Name DnsResolver)) {
        Import-Module (Join-Path $PSScriptRoot '..' 'output' 'DnsResolver.psd1') -ErrorAction Stop
    }

    $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters +
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

    $commands = foreach ($command in Get-Command -Module DnsResolver -CommandType Cmdlet) {
        @{
            Name       = $command.Name
            Parameters = @(
                $command.Parameters.Keys.Where({ $_ -notin $commonParameters }) |
                    ForEach-Object { @{ CommandName = $command.Name; ParameterName = $_ } }
            )
        }
    }

    $markdownFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'docs' 'en-US') -Filter '*.md' -Recurse -File |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

BeforeAll {
    if (-not (Get-Module -Name DnsResolver)) {
        Import-Module (Join-Path $PSScriptRoot '..' 'output' 'DnsResolver.psd1') -ErrorAction Stop
    }
    $script:module = Get-Module -Name DnsResolver
}

Describe 'Module help' -Tag 'Help' {
    It 'Ships a MAML help file for the binary module' {
        Join-Path $module.ModuleBase 'en-US' 'DnsResolver.dll-Help.xml' | Should -Exist
    }
}

Describe 'Help for <Name>' -Tag 'Help' -ForEach $commands {
    BeforeAll {
        $help = Get-Help -Name $Name -Full
    }

    It 'Is loaded from the help file, not auto-generated' {
        # Auto-generated help has no description and a synopsis equal to the syntax.
        $help.description | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -BeLike "$Name *"
    }

    It 'Has a synopsis' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Has a description' {
        ($help.description.Text -join '') | Should -Not -BeNullOrEmpty
    }

    It 'Has examples that use the command' {
        $help.examples.example | Should -Not -BeNullOrEmpty
        foreach ($example in $help.examples.example) {
            # PlatyPS 1.x puts the code fence in introduction rather than code.
            $text = @($example.code) + $example.introduction.Text + $example.remarks.Text -join "`n"
            $text | Should -Match ([regex]::Escape($Name)) -Because $example.title
        }
    }

    It 'Documents only parameters that exist on the command' {
        $actual = (Get-Command -Name $Name).Parameters.Keys
        $help.parameters.parameter.name | Where-Object { $_ -notin $actual } | Should -BeNullOrEmpty
    }

    Context 'Parameter -<ParameterName>' -ForEach $Parameters {
        BeforeAll {
            $parameterHelp = $help.parameters.parameter | Where-Object name -EQ $ParameterName
        }

        It 'Is documented' {
            $parameterHelp | Should -Not -BeNullOrEmpty
        }

        It 'Has a description' {
            ($parameterHelp.description.Text -join '') | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Markdown source <Name>' -Tag 'Help' -ForEach $markdownFiles {
    It 'Has no unfilled PlatyPS placeholders' {
        $Path | Should -Not -FileContentMatch '\{\{.*\}\}'
    }
}
