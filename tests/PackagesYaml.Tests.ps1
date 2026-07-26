#Requires -Version 5.1
Describe 'PackagesYaml' {
    BeforeAll {
        $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'helpers\PackagesYaml.psm1'
        Import-Module $modulePath -Force
    }

    It 'parses package ids, comments, and categories from decorative headers' {
        $lines = @(
            'packages:'
            '  # -- Development tools & languages ----'
            '  development:'
            '    - Git.Git # Git version control'
            '    - OpenJS.NodeJS'
            '  browsers:'
            '    - Mozilla.Firefox # browser'
        )

        $entries = @(Parse-PackagesYamlLines -Lines $lines)
        $entries.Count | Should -Be 3
        $entries[0].Id | Should -Be 'Git.Git'
        $entries[0].Comment | Should -Be 'Git version control'
        $entries[0].Category | Should -Be 'Development tools & languages'
        $entries[0].AllowPrerelease | Should -BeFalse
        $entries[1].Id | Should -Be 'OpenJS.NodeJS'
        $entries[2].Category | Should -Be 'Browsers'
    }

    It 'humanizes category keys when no decorative header is present' {
        $lines = @(
            'packages:'
            '  cloud_infrastructure:'
            '    - Microsoft.AzureCLI'
        )

        $entries = @(Parse-PackagesYamlLines -Lines $lines)
        $entries[0].Category | Should -Be 'Cloud Infrastructure'
    }

    It 'parses @prerelease opt-in from comments' {
        $lines = @(
            'packages:'
            '  development:'
            '    - Some.Package # nightly build @prerelease'
        )

        $entries = @(Parse-PackagesYamlLines -Lines $lines)
        $entries[0].AllowPrerelease | Should -BeTrue
        $entries[0].Comment | Should -Be 'nightly build'
    }

    It 'returns empty array for empty input' {
        $entries = @(Parse-PackagesYamlLines -Lines @())
        $entries.Count | Should -Be 0
    }

    It 'skips blank lines and full-line comments' {
        $lines = @(
            '# header'
            ''
            'packages:'
            '  development:'
            '    # note'
            '    - Git.Git'
        )

        $entries = @(Parse-PackagesYamlLines -Lines $lines)
        $entries.Count | Should -Be 1
        $entries[0].Id | Should -Be 'Git.Git'
    }
}
