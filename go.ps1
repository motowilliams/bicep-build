[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @("clean", "lint", "format", "compile", "build", "uncommited-check", "verify-version-files", "add-module", "publish-modules", "publish-all-modules") | Where-Object { $_ -like "$wordToComplete*" }
        })]
    [string[]] $Tasks,
    [string] $ModuleDirectory = "modules", # Default to current directory if not specified
    [string] $RegistryUri = $env:AZURE_BICEP_REGISTRYURI
)

$rootBicepFile = "main.bicep"
$versionFileName = "version.json"

# Helper function to process files
function ProcessFiles {
    param (
        [string]$TaskName,
        [string]$FileExtension,
        [scriptblock]$Action
    )

    Write-Line
    Write-Host "Running $TaskName Task"
    Write-Line
    Get-ChildItem -Path $ModuleDirectory -Recurse -Include *.$FileExtension | ForEach-Object {
        & $Action $_
        Write-Host " - $TaskName completed for: $(Resolve-Path -Relative -Path $_.FullName)"
    }
    # Write-Host "$TaskName Task completed"
    Write-Line
}

function Get-ChangedModules {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $BaseBranch = "master",
        [switch] $ShowAll
    )

    if ($ShowAll) {
        #this is a directory listing that will run as xplat
        $files = Get-ChildItem -Recurse (Join-Path -Path $ModuleDirectory -ChildPath "*" -AdditionalChildPath $versionFileName)
    }
    else {
        # Get the current branch name
        $currentBranch = git rev-parse --abbrev-ref HEAD
        Write-Host "Comparing changes between $BaseBranch and $currentBranch"

        # Get list of changed files between branches / filter by git path output vs platform specific separator
        # Note: git diff --name-only will only show files that are different between the two branches
        $files = git diff --name-only $BaseBranch $currentBranch | Where-Object { $_ -like "$ModuleDirectory/*/$versionFileName" }
    }

    $files = $files | ForEach-Object { (Get-Item -Path $_).Directory }

    $changeModules = $files | ForEach-Object {
        [PSCustomObject]@{
            ModulePath     = $_.FullName
            BicepFile      = Join-Path -Path $_.FullName -ChildPath $rootBicepFile
            VersionFile    = Join-Path -Path $_.FullName -ChildPath $versionFileName
            ModuleName     = $_.Name
            ModuleCategory = $_.Parent.Name
            ModuleVersion  = Get-Content (Join-Path -Path $_.FullName -ChildPath $versionFileName) | ConvertFrom-Json | Select-Object -ExpandProperty version
        }
    }

    Write-Output $changeModules
}

function Publish-Module {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]$Module
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
}

function Clean {
    Write-Line
    Write-Host "Running clean task..."
    Write-Line
    $includeFiles = ("*.sarif","*.tmp","*.json","*.bicep")
    $excludeFiles = ("version.json","main.bicep")
    # Delete all *.sarif files in the project
    Get-ChildItem -Path $ModuleDirectory -Recurse -Include $includeFiles -Exclude $excludeFiles | ForEach-Object {
        Write-Host " - Deleting: $(Resolve-Path -Relative -Path $_.FullName)"
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Clean task completed. All $($includeFiles -join ", ") files have been deleted from $ModuleDirectory. Excluding $($excludeFiles -join ", ")."
    Write-Line
}

function Lint {
    ProcessFiles -TaskName "lint" -FileExtension "bicep" -Action {
        param ($FilePath)
        $lintFile = "$($FilePath.Directory.Parent.Name).$($FilePath.Directory.Name).sarif"
        $lintFile = Join-Path -Path $FilePath.DirectoryName -ChildPath $lintFile
        New-Item -ItemType File -Path $lintFile -Force | Out-Null
        $lintFileRelative = Resolve-Path -Relative -Path $lintFile
        $filePathRelative = Resolve-Path -Relative -Path $FilePath
        Write-Host " - linting file $filePathRelative to $lintFileRelative"
        bicep lint $FilePath --diagnostics-format sarif | Out-File -FilePath $lintFile -Encoding ascii -Force
        $results = Get-Content -Path $lintFile -Raw | ConvertFrom-Json
        if ($results.runs[0].results.Count -eq 0) {
            Write-Host " - no linting issues found in $filePathRelative. Removing $lintFileRelative"
            Remove-Item -Path $lintFile -Force
        }
        else {
            Write-Host " - linting issues found in $($filePathRelative): $($results | ConvertTo-Json -Depth 99)"
            return
        }
    }
}

function Format {
    ProcessFiles -TaskName "format" -FileExtension "bicep" -Action {
        param ($FilePath)
        bicep format $FilePath --outfile $FilePath
    }
}

function Compile {
    ProcessFiles -TaskName "compile" -FileExtension "bicep" -Action {
        param ($FilePath)
        bicep build $FilePath --stdout | Out-Null
        $errorCode = $LASTEXITCODE
        if ($LASTEXITCODE -ne 0) {
            Write-Error "==================== COMPILATION FAILED ==========================="
            Write-Error "Compilation failed for: $FilePath. Check the Bicep file for errors."
            Write-Error "==================================================================="
            throw $errorCode
        }
    }
}

function CheckModuleGitIndex {
    param (
        [string]$Path
    )

    Write-Line
    Write-Host "Running uncommited-check task..."
    Write-Line

    # Run git status to check if the index is dirty
    $gitStatus = git status --porcelain

    if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
        # Check if the specified path exists in the git status output
        if ($gitStatus -match [regex]::Escape($Path)) {
            Write-Warning "uncommited-check failed: There are uncommitted changes in the specified path: $Path."
            Write-Warning "Ensure all bicep files are formatted correctly and with LF endings before committing."
            Write-Warning "Ensure no linting report files are present in the module directory."
            Write-Warning "Uncommitted changes:"
            $gitStatus | Where-Object { $_ -like "*$Path*" } | ForEach-Object {
                Write-Warning "- $($_.Trim())"
            }
            Write-Line
            exit 1
        }
    }

    Write-Host "uncommited-check task completed. No uncommitted changes detected in the specified path: $Path"
    Write-Line
}

function VerifyVersionFiles {
    Write-Line
    Write-Host "Running verify-version-files task..."
    Write-Line

    # Define the regex patterns for valid version formats
    $validVersionPatterns = @(
        '^\d{4}-\d{2}-\d{2}$', # Format: YYYY-MM-DD
        '^\d{4}-\d{2}-\d{2}-preview$' # Format: YYYY-MM-DD-preview
    )

    $formatExample = "(format YYYY-MM-DD / YYYY-MM-DD-preview)"

    # Get all Bicep module files
    $bicepFiles = Get-ChildItem -Path $ModuleDirectory -Recurse -Include *.bicep

    foreach ($bicepFile in $bicepFiles) {
        $versionFilePath = Join-Path -Path $bicepFile.DirectoryName -ChildPath $versionFileName

        if (-not (Test-Path $versionFilePath)) {
            Write-Error "Missing $versionFileName file for module: $($bicepFile.FullName)"
            Write-Line
            exit 1
        }

        # Validate the version file
        try {
            $versionData = Get-Content -Path $versionFilePath | ConvertFrom-Json

            if (-not $versionData.version) {
                Write-Error "$versionFileName file is missing the 'version' $formatExample property: $versionFilePath"
                Write-Line
                exit 1
            }

            $isValidVersion = $false
            foreach ($pattern in $validVersionPatterns) {
                if ($versionData.version -match $pattern) {
                    $isValidVersion = $true
                    break
                }
            }

            if (-not $isValidVersion) {
                Write-Error "Invalid version format in file: $versionFilePath. Found: $($versionData.version). Expected format: $formatExample"
                Write-Line
                exit 1
            }

        }
        catch {
            Write-Error "Failed to parse $versionFileName file: $versionFilePath. Error: $_"
            Write-Line
            exit 1
        }
    }

    Write-Host "verify-version-files task completed successfully. All $versionFileName files are valid."
    Write-Line
}

function Write-Line {
    Write-Host ("-" * 72) -ForegroundColor Gray
}

function Get-CategoryDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path,

        [Parameter(Mandatory = $false)]
        [string]$Title = "Select a directory:",

        [Parameter(Mandatory = $false)]
        [string]$NewDirPrompt = "Enter name for new module category:"
    )


    # Ensure path exists
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "The specified path does not exist or is not a directory: $Path"
        return $null
    }

    # Get all directories in the specified path
    $directories = Get-ChildItem -Path $Path -Directory | Sort-Object Name

    if ([System.String]::IsNullOrEmpty($directories)) {
        # User selected Create New Category
        Write-Host $NewDirPrompt -ForegroundColor Cyan
        $newDirName = Read-Host

        if ([string]::IsNullOrWhiteSpace($newDirName)) {
            Write-Host "No directory name provided. Operation cancelled." -ForegroundColor Yellow
            return $null
        }
        return $newDirName
    }

    # Clear console and display header
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "Existing module categories" -ForegroundColor Cyan
    Write-Line

    # Display directories with indices
    $index = 1
    foreach ($dir in $directories) {
        Write-Host "$index. $($dir.Name)"
        $index++
    }

    Write-Line
    # Add create new directory option
    Write-Host "N. Create New Category Directory" -ForegroundColor Green
    $createNewDirIndex = 'N'

    # Add cancel option
    Write-Host "C. Cancel" -ForegroundColor Red
    $cancelIndex = 'C'

    Write-Host ("-" * 50) -ForegroundColor Gray

    # Get user selection with input validation
    $validSelection = $false
    $selection = $null

    while (-not $validSelection) {
        $input = Read-Host "Enter selection (1-$index, N, C)"

        # Validate input is a number or 'N'/'C'
        if ($input -match '^(\d+|N|C)$') {
            $selection = $input

            # Validate number is in range or is 'N'/'C'
            if (($selection -ge 1 -and $selection -le $index) -or $selection -eq $createNewDirIndex -or $selection -eq $cancelIndex) {
                $validSelection = $true
            }
            else {
                Write-Host "Invalid selection. Please enter a number between 1 and $index, or $createNewDirIndex/$cancelIndex." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Invalid input. Please enter a number, $createNewDirIndex, or $cancelIndex." -ForegroundColor Yellow
        }
    }

    # Process the user's selection
    if ($selection -eq 'C') {
        # User selected Cancel
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }
    elseif ($selection -eq 'N') {
        # User selected Create New Category
        Write-Host $NewDirPrompt -ForegroundColor Cyan
        $newDirName = Read-Host

        if ([string]::IsNullOrWhiteSpace($newDirName)) {
            Write-Host "No directory name provided. Operation cancelled." -ForegroundColor Yellow
            return $null
        }
        return $newDirName
    }
    else {
        # User selected an existing directory
        $selectedDir = $directories[$selection - 1]
        return $selectedDir.Name
    }
}

function AddModule {
    Write-Line; Write-Host "Running add-module task..."

    $categoryName = Get-CategoryDirectory -Path $ModuleDirectory -Title "Select a category to add a module to:" -NewDirPrompt "Enter name for new category:"
    if ([System.String]::IsNullOrWhiteSpace($categoryName)) {
        Write-Host "No category selected. Exiting add-module task."
        return
    }

    # start building the module path, first with the category
    $modulePath = Join-path -Path $moduleDirectory -ChildPath $categoryName

    # Prompt for module name
    $moduleName = Read-Host "Enter the name of the new module"
    if ([string]::IsNullOrWhiteSpace($moduleName)) {
        Write-Host "No module name provided. Exiting add-module task."
        exit 0
    }

    # continue building the module path, adding the module name
    $modulePath = Join-Path -Path $modulePath -ChildPath $moduleName

    if (Test-Path -Path $modulePath) {
        Write-Host "Module '$moduleName' already exists under '$categoryName'. Exiting add-module task." -ForegroundColor Yellow
        return
    }

    # Create blank main.bicep file
    $mainBicepPath = Join-Path -Path $modulePath -ChildPath "main.bicep"
    New-Item -ItemType File -Path $mainBicepPath -Force | Out-Null

    # Create version file with current date and preview flag
    $versionFilePath = Join-Path -Path $modulePath -ChildPath $versionFileName
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $versionContent = @{ version = "$currentDate-preview" } | ConvertTo-Json -Depth 99
    New-Item -ItemType File -Path $versionFilePath -Value $versionContent -Force | Out-Null

    Write-Host "Module '$moduleName' has been successfully added under '$categoryName'."
}

function Build {
    Write-Host "Running build task..."
    # Aggregate task: lint, format, and compile
    Clean
    Lint
    Format
    Compile
    VerifyVersionFiles
    CheckModuleGitIndex -Path $ModuleDirectory
    Write-Host "Build task completed."
}

# Task runner logic
if ($Tasks -contains "add-module" -and $Tasks.Count -gt 1) {
    Write-Error "The 'add-module' task cannot be combined with other tasks. Please run it separately."
    exit 1
}

if ($null -eq $Tasks -or ($Tasks.Count -eq 0)) {
    Build
}

foreach ($Task in $Tasks) {
    switch ($Task.Trim().ToLower()) {
        "build" { Build }
        "clean" { Clean }
        "compile" { Compile }
        "format" { Format }
        "lint" { Lint }
        "uncommited-check" { CheckModuleGitIndex -Path $ModuleDirectory }
        "verify-version-files" { VerifyVersionFiles }
        "add-module" { AddModule }
        "publish-modules" { Get-ChangedModules | Publish-Module }
        "publish-all-modules" { Get-ChangedModules -ShowAll | Publish-Module }
        default { Write-Error "Unknown task: $Task" }
    }
}
