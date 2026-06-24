$ErrorActionPreference = 'Stop'

Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

$publicFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File |
    ForEach-Object { $_.BaseName })

Export-ModuleMember -Function $publicFunctions
