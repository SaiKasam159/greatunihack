# Regenerate the fake dataset and run the model + charts
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
python src/generate_data.py
python src/model.py
Write-Host ""
Write-Host "Done. Charts in reports\ - open the desktop app with: python GUI.py"
