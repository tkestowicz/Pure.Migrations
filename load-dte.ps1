$libs = "envdte.dll", "envdte80.dll", "envdte90.dll", "envdte100.dll"
function LoadDTELibs {
    param(
        $path = "\Common Files\Microsoft Shared\MSEnv\PublicAssemblies"
    )

    Process {
        $libs |
            ForEach {
                $dll = Join-Path "$env:ProgramFiles\$path" $_

                if(-not (Test-Path $dll)) {
                    $dll = Join-Path "${env:ProgramFiles(x86)}\$path" $_
                }

                Add-Type -Path $dll -PassThru | Where {$_.IsPublic -and $_.BaseType} | Sort Name | Out-Null
            }

        $global:dte = [System.Runtime.InteropServices.Marshal]::GetActiveObject("VisualStudio.DTE.12.0")
    }     
}

LoadDTELibs