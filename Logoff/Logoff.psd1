@{
    RootModule        = 'Logoff.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a4f8c2e1-9b3d-4a6f-8c7e-2d1b5e9f0a3c'
    Author            = 'logoff'
    Description       = 'Gentle user logoff before scheduled Windows server reboots.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-LoggedOnSession', 'Invoke-GentleLogoff')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
