[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(ValueFromPipeline)]
    [PSCustomObject]$Module,
    [string] $RegistryUri = $env:AZURE_BICEP_REGISTRYURI,
    [switch] $EnableLint
)

begin {
    # Check if the Az module is available
    if (-not (Get-Module -Name Az -ListAvailable)) {
        Write-Error "The Az module is not installed. Please install it using 'Install-Module -Name Az' before running this script."
        return
    }

    $RegistryUri = $RegistryUri -replace '^br:', '' # Remove 'br:' prefix if present
    if ([System.String]::IsNullOrEmpty($RegistryUri)) {
        throw "The registry name is not specified. Please supply the Registry argument or set the AZURE_BICEP_REGISTRY environment variable."
        return
    }
}

process {

    if ($EnableLint) {
        $lintFile = "$($Module.ModuleCategory).$($Module.ModuleName).sarif"
        Write-Host "Running linting on $($Module.BicepFile) to $lintFile"
        # Run Bicep linting on the module file / no option to redirect to stdout
        # Redirecting to a file to avoid console output
        bicep lint $Module.BicepFile --diagnostics-format sarif | Out-File -FilePath $lintFile -Encoding ascii -Force
        $results = Get-Content -Path $lintFile -Raw | ConvertFrom-Json
        if ($results.runs[0].results.Count -eq 0) {
            Write-Host "No linting issues found in $($Module.BicepFile)"
            Remove-Item -Path $lintFile -Force
        }
        else {
            Move-Item -Path $lintFile -Destination $(Get-Item -Path $PSScriptRoot).Parent.FullName -Force
            Write-Host "Linting issues found in $($Module.BicepFile): $($results | ConvertTo-Json -Depth 99)"
            return
        }
    }

    # Ensure the Az module is imported
    if (-not (Get-Module -Name Az -ListAvailable)) {
        Write-Error "The Az module is not installed. Please install it using 'Install-Module -Name Az' before running this script."
        return
    }

    # Construct the Azure Bicep registry path
    $RegistryTarget = "br:$RegistryUri/bicep/$($Module.ModuleCategory)/$($Module.ModuleName):$($Module.ModuleVersion)"

    # Use ShouldProcess to support WhatIf
    $publishMessage = "Publishing module $($Module.ModuleName) from path: $($Module.ModulePath) to $RegistryTarget"
    Write-Host "Starting: $publishMessage"
    if ($PSCmdlet.ShouldProcess($publishMessage)) {
        try {
            # Connect to the Azure Bicep registry to keep the session alive
            Connect-AzContainerRegistry -Name ($RegistryUri -replace '.azurecr.io', '') | Out-Null

            # Publish the Bicep module to the Azure Bicep registry
            Publish-AzBicepModule -FilePath $Module.BicepFile -Target $RegistryTarget -WithSource -Force
            Write-Host "Success: $publishMessage"
        }
        catch {
            throw "Failed: $publishMessage. Error: $LASTERROR"
        }
    }
    else {
        Write-Host "What if: Skipping $publishMessage"
    }
}
