$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$venvPython = Join-Path $repositoryRoot ".venv\Scripts\python.exe"
$python = if (Test-Path -LiteralPath $venvPython) { $venvPython } else { "python" }

& $python (Join-Path $PSScriptRoot "ci.py")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
