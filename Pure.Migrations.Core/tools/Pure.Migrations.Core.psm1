﻿param(
    [Parameter(Mandatory=$true)]
    $driver,
    [Parameter(Mandatory=$true)]
    $coreToolsPath,
    [Parameter(Mandatory=$true)]
    $packagesPath,
    [Parameter(Mandatory=$true)]
    $project
)

$solutionPath = Split-Path $DTE.Solution.Properties.Item('Path').Value

Import-Module $driver -ArgumentList @($packagesPath, $project) -Force -DisableNameChecking
Import-Module $coreToolsPath\Pure.Migrations.Driver.Core.psd1 -ArgumentList @($driver, $project) -Force -DisableNameChecking

$scriptTypeEnum = @{
      Migration = 1
      Revert = 2
      Data = 3
   }

function new-migration( 
    [Parameter(Mandatory=$true)]
    $name,
    [Parameter(Mandatory=$true)]
    $project,
    [Parameter(Mandatory=$false)]
    $migrationsDir = "Migrations",
    [switch]
    $force = $false,
    [switch]
    $withData = $false
)
{
    try{
        $migrationId = generate-id    
        $name = escape-name $name
        $isNameUnique = is-migration-name-unique $migrationId $name

        Write-Host "Creating migration '$name' ..." -ForegroundColor Gray
    
        if($isNameUnique -eq $false)
        {
            throw "Name of the migration must be unique. Migration with name '$name' already exists."
        }

        $csproj = find-project-by-name $project

        [xml] $csprojXml = get-content $csproj.FullName

        $itemGroup = ensure-item-group $csprojXml
   
        create-migration $csprojXml $itemGroup $migrationId
        create-additional-script $scriptTypeEnum.Revert $csprojXml $itemGroup $migrationId 

        if($withData)
        {
            create-additional-script $scriptTypeEnum.Data $csprojXml $itemGroup $migrationId 
        }

        $csprojXml.Save($csproj.FullName)

        Write-Host "Migration successfully created." -ForegroundColor DarkGreen
    }
    catch
    {
        write-host $_.Exception.Message -ForegroundColor Red
    }
    
}

function migrate-database( 
        [Parameter(Mandatory=$true)]
        $project,
        [Parameter(Mandatory=$false)]
        $migrationsDir = "Migrations",
        [Parameter(Mandatory=$false)]
        $connectionStringName,
        [Parameter(Mandatory=$false)]
        $targetMigration,
        [switch]
        $detailed
    )
{
    try{
        Write-Host "Updating database, pass '-detailed' to see detailed output..." -ForegroundColor Gray
        
        $startupProject = find-startup-project
        $migrationsDir = find-migrations-directory
        $migrationsToApply = find-migrations $migrationsDir
        $connectionString = find-connection-string $startupProject

        $cmd = create-command $connectionString    

        try{
            $appliedMigrations = initialize-versioning $cmd

            if([string]::IsNullOrEmpty($targetMigration) -eq $false){

                $lastMigrationToApply = $migrationsToApply | where { (get-migration-name $_) -eq $targetMigration } | Select-Object -First 1

                if($lastMigrationToApply -eq $null)
                {
                    Write-Host "Migration named '$targetMigration' does not exist." -ForegroundColor Red
                    return
                }

                $lastMigrationId = get-migration-id $lastMigrationToApply

                $migrationsToApply = $migrationsToApply | where { (get-migration-id $_) -le $lastMigrationId }
            }

            $notAppliedMigrations = $migrationsToApply | ? { $appliedMigrations -notcontains (get-migration-id $_) }
        
            if($notAppliedMigrations.Count -eq 0)
            {
                Write-Host "Database is up to date." -ForegroundColor Gray
                return
            }

            Write-Host "Following migrations will be applied: " -ForegroundColor DarkYellow
            Write-host (($notAppliedMigrations| Select-Object -ExpandProperty Name) -join ", ")
        
            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            foreach($migration in $notAppliedMigrations)
            {           
                execute-migration $migration $appliedMigrations
            }

            $watch.Stop()

            Write-Host "All migrations successfully applied." -ForegroundColor DarkGreen
            Write-host ([string]::Format("Migration took {0} seconds.", $watch.Elapsed.Seconds)) -ForegroundColor Gray

            $cmd.Transaction.Commit()
        }
        catch{
            write-host $_.Exception.Message -ForegroundColor Red

            $cmd.Transaction.Rollback()        
        }
        finally{
            $cmd.Connection.Close()
        }   
    }
    catch
    {
        write-host $_.Exception.Message -ForegroundColor Red
    }
}

function revert-database( 
        [Parameter(Mandatory=$true)]
        $project,
        [Parameter(Mandatory=$false)]
        $migrationsDir = "Migrations",
        [Parameter(Mandatory=$false)]
        $connectionStringName,
        [Parameter(Mandatory=$false)]
        $targetMigration,
        [switch]
        $detailed
    )
{
    try{
        Write-Host "Reverting database, pass '-detailed' to see detailed output..." -ForegroundColor Gray
        
        if([string]::IsNullOrEmpty($targetMigration))
        {
            throw "Target migration not specified."
        }

        $startupProject = find-startup-project
        $migrationsDir = find-migrations-directory
        $migrations = find-revert-migrations $migrationsDir ([ref] $targetMigration)
        $connectionString = find-connection-string $startupProject

        $cmd = create-command $connectionString    

        try
        {
            $appliedMigrations = initialize-versioning $cmd
            
            $migrationsToRevert = $migrations | where { $appliedMigrations -contains (get-migration-id $_) }
            
            if($migrationsToRevert.Count -eq 0)
            {
                 Write-Host "Database is up to date." -ForegroundColor Gray
                 return
            }

            check-revert-integrity $migrations $appliedMigrations
            
            Write-Host "Following migrations will be reverted: " -ForegroundColor DarkYellow
            Write-host (($migrationsToRevert | Select-Object -ExpandProperty Name) -join ", ")

            $watch = [System.Diagnostics.Stopwatch]::StartNew()

            foreach($migration in $migrationsToRevert)
            {              
                execute-revert $migration $appliedMigrations
            }

            $watch.Stop()

            Write-Host ("Database reverted to '"+$targetMigration.Name+"' migration.") -ForegroundColor DarkGreen
            Write-host ([string]::Format("Revert took {0} seconds.", $watch.Elapsed.Seconds)) -ForegroundColor Gray

            $cmd.Transaction.Commit()
        }
        catch{
            write-host $_.Exception.Message -ForegroundColor Red

            $cmd.Transaction.Rollback()        
        }
        finally{
            $cmd.Connection.Close()
        } 
    }
    catch
    {
        write-host $_.Exception.Message -ForegroundColor Red
    }
}

function check-revert-integrity($migrationsOnDisk, $migrationsInDatabase){
    
    $migrationsOnDisk = $migrationsOnDisk | foreach { get-migration-id $_ }

    $migrationsPresentInDatabase = $migrationsOnDisk | where { $migrationsInDatabase -contains $_ }

    $diff = $migrationsOnDisk | where { $migrationsPresentInDatabase -notcontains $_ }

    if($diff.Count -gt 0)
    {    
        throw "Database cannot be reverted to '"+$targetMigration.Name+"' migration. Inconsistency detected between migrations and current schema version."
    }
     
    $migrationsWhichShouldBePresentOnDisk = $migrationsInDatabase | where { $_ -gt $targetMigration.Id }

    $diff = $migrationsWhichShouldBePresentOnDisk | where { $migrationsOnDisk -notcontains $_ }
    
    if($diff.Count -gt 0)
    {
        throw "Database cannot be reverted to '"+$targetMigration.Name+"' migration. Inconsistency detected between migrations and current schema version."
    }
}

function execute-revert($migration, $appliedMigrations)
{
    $name = get-migration-name $migration
    $migrationId = get-migration-id $migration

    [System.IO.FileInfo] $migrationFile = get-script-fullpath $migration.Name

    Write-Host "Reverting migration '$name'..." -ForegroundColor Gray

    revert-migration  $migrationFile $migrationId $cmd $detailed.IsPresent  

    $appliedMigrations = $appliedMigrations | where { $_ -ne $migrationId }

    if($detailed.IsPresent)
    {
        Write-Host "Migration '$name' reverted." -ForegroundColor Gray
    }
}

function execute-migration($migration, $appliedMigrations)
{
    $name = get-migration-name $migration
    $migrationId = get-migration-id $migration

    $canBeApplied = none($appliedMigrations | where { $_ -gt $migrationId })
               
    if($canBeApplied)
    {
        Write-Host "Executing migration '$name'..." -ForegroundColor Gray
            
        [System.IO.FileInfo] $migrationFile = get-script-fullpath $migration.Name

        Write-Host "--- Schema migration" -ForegroundColor Gray

        run-migration $migrationFile $migrationId $cmd $detailed.IsPresent
            
        $data = find-data-script $name $migrationId

        if($data)
        {
            Write-Host "--- Executing seed" -ForegroundColor Gray
            import-data $data $cmd $detailed.IsPresent
        }          

        if($detailed.IsPresent)
        {
            Write-Host "Migration '$name' executed." -ForegroundColor Gray
        }
    }
    else{
        throw "Migration '$name' cannot be applied because newer migration has been already applied."
    }

    if($name -eq $targetMigration)
    {
        break
    }
}

function none($result)
{
    return ($result | Group).Count -eq 0
}

function find-connection-string($startupProject)
{
    $startupProjectDir = ([System.IO.FileInfo] $startupProject.FullName).Directory
    $config = $startupProject.ProjectItems | where { is-config $_ } | select -First 1
    $mapping = New-Object System.Configuration.ExeConfigurationFileMap
   
    $cfgPath = Join-Path $startupProjectDir.FullName $config.Name -Resolve
    $mapping.ExeConfigFilename = $cfgPath

    $config = [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($mapping, [System.Configuration.ConfigurationUserLevel]::None)
    
    if($config.ConnectionStrings.ConnectionStrings.Count -eq 0)
    {
        throw "Configuration loaded from $(startupProject.Name) does not contain any connection string."
    }

    if([string]::IsNullOrEmpty($connectionStringName))
    {
        return $config.ConnectionStrings.ConnectionStrings[0]
    }

    $connectionString = $config.ConnectionStrings.ConnectionStrings | where { $_.Name.ToLower() -eq $connectionStringName.ToLower() } | select -First 1
    
    if([string]::IsNullOrEmpty($connectionString))
    {
        throw "Connection string named '$connectionStringName' is not present in $cfgPath file."
    }

    return $connectionString
}

function find-migrations-directory
{    
    $project = $dte.Solution.Projects | where { $_.Name -eq $project } | select ProjectItems
    
    return $project.ProjectItems | where { $_.Name -eq $migrationsDir } | select -First 1
}

function find-migrations($migrationsDir)
{
    $migrationsDir.ProjectItems | where { $_.Name -notmatch "^[0-9]+_(data|revert)_.*.sql$" }
}

function find-revert-migrations($migrationsDir, [ref]$targetMigration)
{
    [System.IO.DirectoryInfo] $migrations = get-migrations-fullpath
    $revertScripts = $migrations.GetFiles() | where { $_.Name -match "[0-9]+_revert_.*.sql" } | Sort-Object Name -Descending

    $oldest = $revertScripts | Select-Object -ExpandProperty Name -First 1

    $target = $revertScripts | where { (get-migration-name $_) -eq $targetMigration.Value } | Select-Object -First 1

    if($target -eq $null)
    {
        throw "Migration named '"+$targetMigration.Value+"' does not exist."
    }
    
    $targetParams = @{
        Id = get-migration-id $target
        Name = $targetMigration.Value
        Migration = $target
    }

    $targetMigration.Value = New-Object -TypeName PsObject -Prop $targetParams

    if($oldest -eq $targetMigration.Value.Migration)
    {
        Write-Host "You are trying to revert database to the oldest migration which is not possible." -ForegroundColor Yellow
        break
    }

    foreach($script in $revertScripts)
    {
        if($script.Name -eq $targetMigration.Value.Migration)
        {
            break
        }   
        
        $script     
    }
}

function find-startup-project
{
    $startupProjectPaths = $dte.Solution.SolutionBuild.StartupProjects
    
    if ($startupProjectPaths)
    {
        if ($startupProjectPaths.Length -eq 1)
        {
            $startupProjectPath = $startupProjectPaths[0]

            if (!(Split-Path -IsAbsolute $startupProjectPath))
            {
                $solutionPath = Split-Path $DTE.Solution.Properties.Item('Path').Value
                $startupProjectPath = Join-Path $solutionPath $startupProjectPath -Resolve
            }

            $startupProject = $dte.Solution.Projects | where { 
            
                try
                {
                    $fullName = $_.FullName
                }
                catch [NotImplementedException]
                {
                    return $false
                }

                if ($fullName -and $fullName.EndsWith('\'))
                {
                    $fullName = $fullName.Substring(0, $fullName.Length - 1)
                }

                return $fullName -eq $startupProjectPath
               
            } | select -First 1

            return $startupProject
        }
        else
        {
            Write-Verbose 'More than one start-up project found.'
        }
    }
    else
    {
        Write-Verbose 'No start-up project found.'
    }
}

function find-data-script($name, $migrationId)
{
    [System.IO.DirectoryInfo] $migrations = get-migrations-fullpath
    [System.IO.FileInfo] $script = $migrations.GetFiles() | where { $_.Name -eq $migrationId+"_data_$name.sql" } | select -First 1

    return  $script
}

function find-project-by-name($projectName)
{
    return $DTE.Solution.Projects | Where { $_.Name -eq $projectName} | select -First 1
}

function get-migrations-fullpath
{
    return [io.path]::combine($solutionPath, $project, $migrationsDir.Name)
}

function get-script-fullpath($name)
{
    return [io.path]::combine((get-migrations-fullpath), $name)
}

function get-migration-id($migration)
{
    $migration.Name -match "^([0-9]+)" | out-null
        
    $timestamp = $($Matches[0])

    return $timestamp
}

function get-migration-name($migration)
{
    $timestamp = get-migration-id $migration
    
    $name = [System.IO.Path]::GetFileNameWithoutExtension($migration.Name)

    $name = $name -replace $timestamp+"_?(revert|data)?_"
    
    return $name
}

function escape-name($name)
{
    return $name -replace "[\s]", "-"
}

function is-config($file)
{
    $fileName = $file.Name.ToLower()
    
    $fileName -eq "app.config" -or $fileName -eq "web.config"
}

function is-migration-name-unique($migrationId, $name)
{
    [System.IO.DirectoryInfo] $dir = [io.path]::Combine($solutionPath, $project, $migrationsDir)

    if($dir.Exists -eq $false)
    {
        $dir.Create()
    }

    ($dir.GetFiles() | where { $_.Name -match "^[0-9]+_"+$name+".sql$" } | Group ).Count -eq 0
}

function generate-id()
{
    $current = (get-date -Format s)

    $current -replace "[T:-]", ""
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

Export-ModuleMember -Function new-migration, migrate-database, revert-database, execute-script, import-data, find-project-by-name