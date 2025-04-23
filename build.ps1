[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$Tasks
)

function Clean {
    Write-Host "Running clean task..."
    # Delete all *.sarif files in the project
    Get-ChildItem -Path . -Recurse -Include *.sarif | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "Clean task completed. All *.sarif files have been deleted."
}

function Lint {
    Write-Host "Running lint task..."
    # Lint all Bicep files in the project
    Get-ChildItem -Path . -Recurse -Include *.bicep | ForEach-Object {
        bicep lint $_.FullName --diagnostics-format sarif | Out-Null
        Write-Host "Linted: $($_.FullName)"
    }
    Write-Host "Lint task completed."
}

function Format {
    Write-Host "Running format task..."
    # Format all Bicep files in the project
    Get-ChildItem -Path . -Recurse -Include *.bicep | ForEach-Object {
        bicep format $_.FullName --outfile $_.FullName --force
        Write-Host "Formatted: $($_.FullName)"
    }
    Write-Host "Format task completed."
}

function Compile {
    Write-Host "Running compile task..."
    # Compile all Bicep files in the project
    Get-ChildItem -Path . -Recurse -Include *.bicep | ForEach-Object {
        bicep build $_.FullName --outfile "$($_.DirectoryName)\$($_.BaseName).json"
        Write-Host "Compiled: $($_.FullName)"
    }
    Write-Host "Compile task completed."
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