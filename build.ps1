[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$Tasks
)

# Helper function to process files
function ProcessFiles {
    param (
        [string]$TaskName,
        [string]$FileExtension,
        [scriptblock]$Action
    )

    Write-Host "Running $TaskName task..."
    Get-ChildItem -Path . -Recurse -Include *.$FileExtension | ForEach-Object {
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
        bicep build $FilePath --outfile "$([System.IO.Path]::ChangeExtension($FilePath, 'json'))"
    }
}

function Build {
    Write-Host "Running build task..."
    # Aggregate task: lint, format, and compile
    Lint
    Format
    Compile
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

# Task runner logic
foreach ($Task in $Tasks) {
    switch ($Task.Trim().ToLower()) {
        "clean" { Clean }
        "lint" { Lint }
        "format" { Format }
        "compile" { Compile }
        "build" { Build }
        "verify-format" { VerifyFormat }
        default { Write-Error "Unknown task: $Task" }
    }
}