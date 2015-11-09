param( 
    [Parameter(Mandatory=$true)]
    $name,
    [Parameter(Mandatory=$true)]
    $project,
    [Parameter(Mandatory=$false)]
    $migrationsDir = "Migrations",
    [switch]
    $force = $false
)

[System.IO.DirectoryInfo] $solutionDir = ([System.IO.FileInfo]$PSCommandPath).Directory.Parent.FullName

Function add-migration([system.string] $name, [System.String] $project, [System.String] $migrationsDir)
{
    $name = $name -replace "[\s]", "-"
    [System.IO.DirectoryInfo] $projectDir = [io.path]::combine($solutionDir.FullName, $project)
    
    $migrationTimestamp = get-timestamp
    $migrationPath = [io.path]::combine($migrationsDir, $migrationTimestamp+"_"+$name+".sql")

    $csproj = $projectDir.GetFiles() | where { $_.FullName.EndsWith(".csproj") }

    [xml] $csprojXml = Get-Content $csproj.FullName
    
    $nm = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $csprojXml.NameTable
    $nm.AddNamespace('x', 'http://schemas.microsoft.com/developer/msbuild/2003')

    [System.Xml.XmlElement] $itemGroup = $csprojXml.SelectNodes('/x:Project/x:ItemGroup', $nm) | select -First 1
    if($itemGroup -eq $null)
    {
        $itemGroup = $csprojXml.CreateElement("ItemGroup", $csprojXml.DocumentElement.NamespaceURI)

        $csprojXml.DocumentElement.AppendChild($itemGroup)
    }

    $newItem = $csprojXml.CreateElement("EmbeddedResource", $csprojXml.DocumentElement.NamespaceURI)
    
    $newItem.SetAttribute("Include", $migrationPath) 
    
    $itemGroup.AppendChild($newItem)
    
    $csprojXml.Save($csproj.FullName)
    
    $fullPath = [io.path]::combine($projectDir.FullName, $migrationPath)
    $migrationsDir = [io.path]::combine($projectDir.FullName, $migrationsDir)
    $migrationsDirExists = Test-Path $migrationsDir
    
    if($migrationsDirExists -eq $false){
        New-Item -ItemType directory -Path $migrationsDir -Force | Out-Null 
    }

    if($force){
        New-Item -ItemType file -Path $fullPath -Force | Out-Null 
    }else{
        New-Item -ItemType file -Path $fullPath | Out-Null 
    }
}



Function get-timestamp(){
    $current = (Get-Date -Format s)

    $current -replace "[T:-]", ""
}

add-migration $name $project $migrationsDir