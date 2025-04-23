[CmdletBinding()]
param(
    [Parameter()]
    [string] $BaseBranch = "master",
    [switch] $ShowAll
)

$modulesRootDirectoryName = "modules"
$rootBicepFile = "main.bicep"
$versionFileName = "version.json"

if ($ShowAll) {
    #this is a directory listing that will run as xplat
    $files = Get-ChildItem -Recurse (Join-Path -Path $modulesRootDirectoryName -ChildPath "*" -AdditionalChildPath $versionFileName)
}
else {
    # Get the current branch name
    $currentBranch = git rev-parse --abbrev-ref HEAD
    Write-Host "Comparing changes between $BaseBranch and $currentBranch"

    # Get list of changed files between branches / filter by git path output vs platform specific separator
    # Note: git diff --name-only will only show files that are different between the two branches
    $files = git diff --name-only $BaseBranch $currentBranch | Where-Object { $_ -like "$modulesRootDirectoryName/*/$versionFileName" }
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
