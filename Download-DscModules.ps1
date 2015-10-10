# Download and install xSharePoint
$branch = 'dev'
$modules = @('xSharePoint', 'xWebAdministration', 'xCredSSP', 'xStorage')

[System.Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null
$modules | Foreach-Object {
    $request = Invoke-WebRequest -Uri https://github.com/PowerShell/$_/archive/$branch.zip
    $request.Content | Set-Content $env:TEMP\$_.zip -Encoding Byte -Force    
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$env:TEMP\$_.zip", "$env:TEMP")
    Rename-Item "$env:TEMP\$_-$branch" -NewName "$env:TEMP\$_"
    If($_ -eq 'xSharePoint') {
        Copy-Item -Path "$env:TEMP\$_\Modules\$_" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules" -Force -Recurse
    } else {
        Copy-Item -Path "$env:TEMP\$_\" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules" -Force -Recurse 
    }
    Remove-Item "$env:TEMP\$_" -Force -Confirm:$false -Recurse
    
}