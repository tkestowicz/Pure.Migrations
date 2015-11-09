param( 
    [Parameter(Mandatory=$true)]
    $name,
    [Parameter(Mandatory=$true)]
    $project,
    [Parameter(Mandatory=$false)]
    $migrationsDir = "Migrations",
    [switch]
    $force = $false,
    [switch]
    $withRevert = $false,
    [switch]
    $withData = $false
)

& "$PSCommandPath\..\load-dte.ps1"

$solutionPath = Split-Path $DTE.Solution.Properties.Item('Path').Value

$scriptTypeEnum = @{
      Migration = 1
      Revert = 2
      Data = 3
   }

function add-migration
{
    $name = escape-name $name
    $csproj = find-project-by-name $project

    [xml] $csprojXml = get-content $csproj.FullName

    $migrationId = generate-id    
    $itemGroup = ensure-item-group $csprojXml
   
    create-migration $csprojXml $itemGroup $migrationId
    
    if($withRevert)
    {
        create-additional-script $scriptTypeEnum.Revert $csprojXml $itemGroup $migrationId 
    }

    if($withData)
    {
        create-additional-script $scriptTypeEnum.Data $csprojXml $itemGroup $migrationId 
    }

    $csprojXml.Save($csproj.FullName)
}

function escape-name($name)
{
    return $name -replace "[\s]", "-"
}

function find-project-by-name($projectName)
{
    return $DTE.Solution.Projects | Where { $_.Name -eq $projectName} | select -First 1
}

function generate-id()
{
    $current = (get-date -Format s)

    $current -replace "[T:-]", ""
}

function create-migration($csProjXml, $itemGroup, $migrationId)
{

    $migrationName = create-script-name $migrationId $scriptTypeEnum.Migration

    $newItem = $csprojXml.CreateElement("EmbeddedResource", $csprojXml.DocumentElement.NamespaceURI)
    
    $newItem.SetAttribute("Include", [io.path]::combine($migrationsDir, $migrationName)) 
    
    $itemGroup.AppendChild($newItem) | Out-Null

    $dir = ensure-directory $migrationsDir

    create-file ([io.path]::combine($dir.FullName, $migrationName))
}

function create-additional-script($scriptType, $csProjXml, $itemGroup, $migrationId)
{
    $migrationName = create-script-name $migrationId $scriptTypeEnum.Migration
    $scriptName = create-script-name $migrationId $scriptType

    $newItem = $csprojXml.CreateElement("EmbeddedResource", $csprojXml.DocumentElement.NamespaceURI)
    
    $newItem.SetAttribute("Include", [io.path]::combine($migrationsDir, $scriptName)) 

    $dependItem = $csprojXml.CreateElement("DependentUpon", $csprojXml.DocumentElement.NamespaceURI)

    $dependItem.InnerText = $migrationName

    $newItem.AppendChild($dependItem) | Out-Null

    $itemGroup.AppendChild($newItem) | Out-Null

    $dir = ensure-directory $migrationsDir

    create-file ([io.path]::combine($dir.FullName, $scriptName))
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

function ensure-directory($dir)
{

    $fullPath = [io.path]::Combine($solutionPath, $project, $dir)

    $dirExists = test-path $fullPath
    
    if($dirExists -eq $false){
        new-item -ItemType directory -Path $fullPath -Force | Out-Null 
    }

    return [System.IO.DirectoryInfo] $fullPath
}

function create-file($fullPath)
{
    
    if($force){
        new-item -ItemType file -Path $fullPath -Force | Out-Null 
    }else{
        new-item -ItemType file -Path $fullPath | Out-Null 
    }

}

function create-script-name($id, $type)
{

    if($type -eq $scriptTypeEnum.Migration){
        return $id+"_"+$name+".sql"
    }

    if($type -eq $scriptTypeEnum.Revert){
        return $id+"_revert_"+$name+".sql"
    }

    if($type -eq $scriptTypeEnum.Data){
        return $id+"_data_"+$name+".sql"
    }

    throw "Unkown script type"
}

add-migration