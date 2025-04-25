[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            @("clean", "lint", "format", "compile", "build", "verify-format", "verify-version-files") | Where-Object { $_ -like "$wordToComplete*" }
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

# Task runner logic
foreach ($Task in $Tasks) {
    switch ($Task.Trim().ToLower()) {
        "build" { Build }
        "clean" { Clean }
        "compile" { Compile }
        "format" { Format }
        "lint" { Lint }
        "verify-format" { VerifyFormat }
        "verify-version-files" { VerifyVersionFiles }
        default { Write-Error "Unknown task: $Task" }
    }
}