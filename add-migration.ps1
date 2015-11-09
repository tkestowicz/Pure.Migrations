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

& "$PSCommandPath\..\load-dte.ps1"

$solutionPath = Split-Path $DTE.Solution.Properties.Item('Path').Value

function add-migration
{
    $name = escape-name $name
    $csproj = find-project
    [xml] $csprojXml = Get-Content $csproj.FullName

    $migrationId = get-timestamp
    
    $itemGroup = ensure-item-group $csprojXml
    $migration = create-migration $csprojXml $itemGroup $migrationId

    $csprojXml.Save($csproj.FullName)
}


function escape-name
{
    return $name -replace "[\s]", "-"
}

function find-project()
{
    return $DTE.Solution.Projects | Where { $_.Name -eq $project } | select -First 1
}

function get-timestamp(){
    $current = (Get-Date -Format s)

    $current -replace "[T:-]", ""
}

function create-migration($csProjXml, $itemGroup, $migrationId){

    $migrationName = $migrationId+"_"+$name+".sql"

    $newItem = $csprojXml.CreateElement("EmbeddedResource", $csprojXml.DocumentElement.NamespaceURI)
    
    $newItem.SetAttribute("Include", [io.path]::combine($migrationsDir, $migrationName)) 
    
    $itemGroup.AppendChild($newItem)

    $dir = ensure-directory $migrationsDir

    create-file ([io.path]::combine($dir.FullName, $migrationName))

    return $migrationPath
}

function ensure-item-group($csProjXml)
{
    $nm = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $csprojXml.NameTable
    $nm.AddNamespace('x', $csprojXml.DocumentElemement.NamespaceURI)

    [System.Xml.XmlElement] $itemGroup = $csprojXml.SelectNodes('/x:Project/x:ItemGroup', $nm) | select -First 1
    if($itemGroup -eq $null)
    {
        $itemGroup = $csprojXml.CreateElement("ItemGroup", $csprojXml.DocumentElement.NamespaceURI)

        $csprojXml.DocumentElement.AppendChild($itemGroup)
    }

    $itemGroup
}

function ensure-directory($dir){

    $fullPath = [io.path]::Combine($solutionPath, $project, $dir)

    $dirExists = Test-Path $fullPath
    
    if($dirExists -eq $false){
        New-Item -ItemType directory -Path $fullPath -Force | Out-Null 
    }

    return [System.IO.DirectoryInfo] $fullPath
}

function create-file($fullPath){
    if($force){
        New-Item -ItemType file -Path $fullPath -Force | Out-Null 
    }else{
        New-Item -ItemType file -Path $fullPath | Out-Null 
    }
}

add-migration