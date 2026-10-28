# Entry point into powershell module
# Dot sourcing the function files to make them available in the module
foreach ($functionFile in (Get-ChildItem -Path "$PSScriptRoot\Functions" -Recurse -Include "*.ps1")) {
    . $functionFile
}