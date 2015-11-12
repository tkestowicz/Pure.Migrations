param( 
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

& "$PSCommandPath\..\load-dte.ps1"

$solutionPath = Split-Path $DTE.Solution.Properties.Item('Path').Value

#todo: dodać ustawianie drivera
if (Get-Module | ?{ $_.Name -eq 'mysql-driver' })
{
    Remove-Module mysql-driver
}

Import-Module (Join-Path $PSCommandPath\.. mysql-driver.psm1) -DisableNameChecking

function update-database
{
    try{
        Write-Host "Updating database, pass '-detailed' to see detailed output..." -ForegroundColor Gray
        
        $startupProject = find-startup-project
        $migrationsDir = find-migrations-directory
        $migrations = find-migrations $migrationsDir
        $connectionString = find-connection-string $startupProject

        $cmd = create-command $connectionString    

        try{
            $appliedMigrations = initialize-versioning $cmd
 
            if(($migrations | group).Count -eq $appliedMigrations.Length)
            {
                Write-Host "Database is up to date." -ForegroundColor Gray
                return
            }
        
            foreach($migration in $migrations)
            {           
                execute-migration $migration $appliedMigrations
            }

            Write-Host "All migrations successfully applied." -ForegroundColor DarkGreen

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

function revert-database
{
    try{
        Write-Host "Reverting database, pass '-detailed' to see detailed output..." -ForegroundColor Gray
        
        if([string]::IsNullOrEmpty($targetMigration))
        {
            throw "Target migration not specified."
        }

        $startupProject = find-startup-project
        $migrationsDir = find-migrations-directory
        $migrations = find-revert-migrations $migrationsDir
        $connectionString = find-connection-string $startupProject

        $cmd = create-command $connectionString    

        try
        {
            $appliedMigrations = initialize-versioning $cmd
        
            if(($migrations | Group).Count -eq 0)
            {
                Write-Host "You are probably trying to revert database to the oldest migration which is not possible." -ForegroundColor Yellow
                Write-Host "Maybe you should use 'update-database' instead." -ForegroundColor Yellow
                break
            }

            $wasAnyReverted = $false
            foreach($migration in $migrations)
            {              
                $wasAnyReverted = execute-revert $migration $appliedMigrations
            }

            if($wasAnyReverted)
            {
                Write-Host "Database reverted to '$targetMigration' migration." -ForegroundColor DarkGreen
            }
            else{
                Write-Host "Database seems to be up-to-date." -ForegroundColor DarkGreen
            }

            $cmd.Transaction.Commit()
        }
        catch{
            write-error $_
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

function execute-revert($migration, $appliedMigrations)
{
    $name = get-migration-name $migration
    $migrationId = get-migration-id $migration

    $isNotAlreadyApplied = none($appliedMigrations | where { $_ -eq $migrationId })

    if($isNotAlreadyApplied)
    {
        return $false
    }

    [System.IO.FileInfo] $migrationFile = get-script-fullpath $migration.Name

    Write-Host "Reverting migration '$name'..." -ForegroundColor Gray

    revert-migration  $migrationFile $migrationId $cmd $detailed.IsPresent  

    if($detailed.IsPresent)
    {
        Write-Host "Migration '$name' reverted." -ForegroundColor Gray
    }

    return $true
}

function execute-migration($migration, $appliedMigrations)
{
    $name = get-migration-name $migration
    $migrationId = get-migration-id $migration
    
    $isNotAlreadyApplied = none($appliedMigrations | where { $_ -eq $migrationId })
             
    if($isNotAlreadyApplied){

        $canBeApplied = none($appliedMigrations | where { $_ -gt $migrationId })
               
        if($canBeApplied)
        {
            Write-Host "Executing migration '$name'..." -ForegroundColor Gray
            
            [System.IO.FileInfo] $migrationFile = get-script-fullpath $migration.Name

            run-migration $migrationFile $migrationId $cmd $detailed.IsPresent
            
            $data = find-data-script $name $migrationId

            if($data)
            {
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

function is-config($file)
{
    $fileName = $file.Name.ToLower()
    
    $fileName -eq "app.config" -or $fileName -eq "web.config"
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

function find-revert-migrations($migrationsDir)
{
    [System.IO.DirectoryInfo] $migrations = get-migrations-fullpath
    $revertScripts = $migrations.GetFiles() | where { $_.Name -match "[0-9]+_revert_.*.sql" } | Sort-Object Name -Descending

    foreach($script in $revertScripts)
    {
        if($script.Name -match $targetMigration)
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

update-database