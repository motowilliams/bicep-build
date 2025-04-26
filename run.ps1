[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @("clean", "lint", "format", "compile", "build", "verify-format", "verify-version-files", "add-module") | Where-Object { $_ -like "$wordToComplete*" }
        })]
    [string[]] $Tasks,
    [string] $ModuleDirectory = "modules"  # Default to current directory if not specified
)

# Helper function to process files
function ProcessFiles {
    param (
        [string]$TaskName,
        [string]$FileExtension,
        [scriptblock]$Action
    )

    Write-Host "Running $TaskName task..."
    Get-ChildItem -Path $ModuleDirectory -Recurse -Include *.$FileExtension | ForEach-Object {
        & $Action $_.FullName
        Write-Host "- $TaskName completed for: $($_.FullName)"
    }
    Write-Host "$TaskName task completed."
}

function Clean {
    Write-Host "Running clean task..."
    # Delete all *.sarif files in the project
    Get-ChildItem -Path . -Recurse -Include *.sarif | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "Clean task completed. All *.sarif files have been deleted."
}

function Lint {
    ProcessFiles -TaskName "lint" -FileExtension "bicep" -Action {
        param ($FilePath)
        bicep lint $FilePath --diagnostics-format sarif | Out-Null
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

function Build {
    Write-Host "Running build task..."
    # Aggregate task: lint, format, and compile
    Clean
    Lint
    Format
    Compile
    VerifyFormat 
    Write-Host "Build task completed."
}

function VerifyFormat {
    Write-Host "Running verify-format task..."
    # Run git status to check if the index is dirty
    $gitStatus = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
        Write-Error "Verify-format failed: There are uncommitted changes after formatting. Ensure all files are formatted correctly before committing."
        exit 1
    }
    Write-Host "Verify-format task completed. No uncommitted changes detected."
}

function VerifyVersionFiles {
    Write-Host "Running verify-version-files task..."

    # Define the regex patterns for valid version formats
    $validVersionPatterns = @(
        '^\d{4}-\d{2}-\d{2}$', # Format: YYYY-MM-DD
        '^\d{4}-\d{2}-\d{2}-preview$' # Format: YYYY-MM-DD-preview
    )

    # Get all Bicep module files
    $bicepFiles = Get-ChildItem -Path $ModuleDirectory -Recurse -Include *.bicep

    foreach ($bicepFile in $bicepFiles) {
        $versionFilePath = Join-Path -Path $bicepFile.DirectoryName -ChildPath "version.json"

        if (-not (Test-Path $versionFilePath)) {
            Write-Error "Missing version.json file for module: $($bicepFile.FullName)"
            exit 1
        }

        # Validate the version.json file
        try {
            $versionData = Get-Content -Path $versionFilePath | ConvertFrom-Json

            if (-not $versionData.version) {
                Write-Error "version.json file is missing the 'version' (format YYYY-MM-DD / YYYY-MM-DD-preview) property: $versionFilePath"
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
                Write-Error "Invalid version format in file: $versionFilePath. Found: $($versionData.version)"
                exit 1
            }

        }
        catch {
            Write-Error "Failed to parse version.json file: $versionFilePath. Error: $_"
            exit 1
        }
    }

    Write-Host "verify-version-files task completed successfully. All version.json files are valid."
}

function Get-CategoryDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path,
            
        [Parameter(Mandatory = $false)]
        [string]$Title = "Select a directory:",
            
        [Parameter(Mandatory = $false)]
        [string]$NewDirPrompt = "Enter name for new directory:"
    )
        
    # Ensure path exists
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "The specified path does not exist or is not a directory: $Path"
        return $null
    }
        
    # Get all directories in the specified path
    $directories = Get-ChildItem -Path $Path -Directory | Sort-Object Name
        
    # Clear console and display header
    Clear-Host
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "Available directories in $Path" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor Gray
        
    # Display directories with indices
    $index = 1
    foreach ($dir in $directories) {
        Write-Host "$index. $($dir.Name)"
        $index++
    }
        
    # Add create new directory option
    Write-Host "$index. Create New Directory" -ForegroundColor Green
    $createNewDirIndex = $index
    $index++
        
    # Add cancel option
    Write-Host "$index. Cancel" -ForegroundColor Red
    $cancelIndex = $index
        
    Write-Host ("-" * 50) -ForegroundColor Gray
        
    # Get user selection with input validation
    $validSelection = $false
    $selection = $null
        
    while (-not $validSelection) {
        $input = Read-Host "Enter selection (1-$index)"
            
        # Validate input is a number
        if ($input -match '^\d+$') {
            $selection = [int]$input
                
            # Validate number is in range
            if ($selection -ge 1 -and $selection -le $index) {
                $validSelection = $true
            }
            else {
                Write-Host "Invalid selection. Please enter a number between 1 and $index." -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Invalid input. Please enter a number." -ForegroundColor Yellow
        }
    }
        
    # Process the user's selection
    if ($selection -eq $cancelIndex) {
        # User selected Cancel
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return $null
    }
    elseif ($selection -eq $createNewDirIndex) {
        # User selected Create New Directory
        Write-Host $NewDirPrompt -ForegroundColor Cyan
        $newDirName = Read-Host
            
        if ([string]::IsNullOrWhiteSpace($newDirName)) {
            Write-Host "No directory name provided. Operation cancelled." -ForegroundColor Yellow
            return $null
        }
            
        $newDirPath = Join-Path -Path $Path -ChildPath $newDirName
            
        # Check if directory already exists
        if (Test-Path -Path $newDirPath -PathType Container) {
            Write-Host "Directory already exists: $newDirPath" -ForegroundColor Yellow
            return $newDirPath
        }
            
        try {
            # Create the new directory
            $newDir = New-Item -Path $newDirPath -ItemType Directory -ErrorAction Stop
            Write-Host "Created new directory: $($newDir.FullName)" -ForegroundColor Green
            return $newDir.FullName
        }
        catch {
            Write-Error "Failed to create directory: $_"
            return $null
        }
    }
    else {
        # User selected an existing directory
        $selectedDir = $directories[$selection - 1]
        Write-Host "Selected directory: $($selectedDir.FullName)" -ForegroundColor Green
        return $selectedDir.FullName
    }
}

function AddModule {
    Write-Host "Running add-module task..."

    Get-CategoryDirectory -Path $ModuleDirectory -Title "Select a category to add a module to:" -NewDirPrompt "Enter name for new category:" -OutVariable CategoryPath
    if (-not $CategoryPath) {
        Write-Host "No category selected. Exiting add-module task."
        return
    }

    # Prompt for module name
    $moduleName = Read-Host "Enter the name of the new module"
    $modulePath = Join-Path -Path $categoryPath -ChildPath $moduleName

    # Create module directory structure
    New-Item -ItemType Directory -Path $modulePath -Force | Out-Null

    # Create blank main.bicep file
    $mainBicepPath = Join-Path -Path $modulePath -ChildPath "main.bicep"
    New-Item -ItemType File -Path $mainBicepPath -Force | Out-Null

    # Create version.json file with current date and preview flag
    $versionFilePath = Join-Path -Path $modulePath -ChildPath "version.json"
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $versionContent = @{ version = "$currentDate-preview" } | ConvertTo-Json -Depth 1
    Set-Content -Path $versionFilePath -Value $versionContent

    Write-Host "Module '$moduleName' has been successfully added under category '$category'."
}

# Task runner logic
if ($Tasks -contains "add-module" -and $Tasks.Count -gt 1) {
    Write-Error "The 'add-module' task cannot be combined with other tasks. Please run it separately."
    exit 1
}

foreach ($Task in $Tasks) {
    switch ($Task.Trim().ToLower()) {
        "build" { Build }
        "clean" { Clean }
        "compile" { Compile }
        "format" { Format }
        "lint" { Lint }
        "verify-format" { VerifyFormat }
        "verify-version-files" { VerifyVersionFiles }
        "add-module" { AddModule }
        default { Write-Error "Unknown task: $Task" }
    }
}