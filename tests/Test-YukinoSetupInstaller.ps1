param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$setupBuilder = Join-Path $ProjectRoot "scripts\New-YukinoSetup.ps1"
$publishScript = Join-Path $ProjectRoot "scripts\Publish-YukinoRelease.ps1"
$readme = Join-Path $ProjectRoot "README.md"
$testRunner = Join-Path $ProjectRoot "tests\Run-YukinoTests.ps1"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

Assert-True (Test-Path -LiteralPath $setupBuilder) "Missing setup installer builder: $setupBuilder"
Assert-True (Test-Path -LiteralPath $publishScript) "Missing release publishing script: $publishScript"

$builderText = [IO.File]::ReadAllText($setupBuilder)
Assert-True $builderText.Contains("Yukino-Setup-") "Setup builder should create a versioned Yukino-Setup executable."
Assert-True $builderText.Contains("Install-YukinoRelease.ps1") "Setup builder should embed the existing release installer script."
Assert-True $builderText.Contains("CreateFromDirectory") "Setup builder should pack release payload files into an embedded zip payload."
Assert-True $builderText.Contains("YUKINO_SETUP_PAYLOAD_V1") "Setup builder should append a discoverable payload marker to the executable."
Assert-True $builderText.Contains("CSharpCodeProvider") "Setup builder should compile a Windows setup executable without adding a project dependency."
Assert-True $builderText.Contains('startInfo.Verb = "runas"') "Setup executable should request administrator elevation for trusted certificate import."

$publishText = [IO.File]::ReadAllText($publishScript)
Assert-True $publishText.Contains("New-YukinoSetup.ps1") "Release publishing should generate the one-file setup executable."
Assert-True $publishText.Contains('$setup') "Release publishing should track the setup executable as a release asset."
Assert-True $publishText.Contains('$assets = @($msix, $certificate, $checksum, $installer, $setup)') "Release assets should include the setup executable."
Assert-True $publishText.Contains("Yukino-Setup-") "Release notes should mention the one-file setup executable."
Assert-True (-not $publishText.Contains("Add-AppxPackage")) "Release publishing should not install packages while generating setup assets."

$readmeText = [IO.File]::ReadAllText($readme)
Assert-True $readmeText.Contains("Yukino-Setup-") "README should document the one-file setup installer for new users."

$runnerText = [IO.File]::ReadAllText($testRunner)
Assert-True $runnerText.Contains("Test-YukinoSetupInstaller.ps1") "The test suite should include the setup installer contract test."

Write-Host "Yukino setup installer test passed."
