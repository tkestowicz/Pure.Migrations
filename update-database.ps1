param( 
    [Parameter(Mandatory=$true)]
    $project,
    [Parameter(Mandatory=$false)]
    $migrationsDir = "Migrations",
    [Parameter(Mandatory=$false)]
    $connectionStringName,
    [Parameter(Mandatory=$false)]
    $targetMigration
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
    $startupProject = find-startup-project
    $migrations = find-migrations
    $connectionString = find-connection-string $startupProject

    $cmd = create-command $connectionString    

    try{
        $appliedMigrations = initialize-versioning $cmd
 
        if($migrations.Length -eq $appliedMigrations.Length)
        {
            Write-Host "Database is up to date."
            return
        }

        foreach($migration in $migrations)
        {
            execute-migration $migration $appliedMigrations
        }

        Write-Host "All migrations successfully applied."

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

function execute-migration($migration, $appliedMigrations)
{
    $name = get-migration-name $migration
    Write-Host $name
    $migrationId = get-migration-id $migration

    $isNotAlreadyApplied = none($appliedMigrations | where { $_ -eq $migrationId })
             
    if($isNotAlreadyApplied){

        $canBeApplied = none($appliedMigrations | where { $_ -gt $migrationId })
               
        if($canBeApplied)
        {
            [System.IO.FileInfo] $migrationFile = get-migration-fullpath $migration

            run-migration $migrationFile $migrationId $cmd 
        }
        else{
            throw "Migration '"+$migration.Name+"' cannot be applied because newer migration has been already applied."
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

function find-migrations
{
    $project = $dte.Solution.Projects | where { $_.Name -eq $project } | select ProjectItems
    $migrationsDir = $project.ProjectItems | where { $_.Name -eq $migrationsDir } | select -First 1
    $migrationsDir.ProjectItems | where { $_.Name -notmatch "^[0-9]+_(data|revert)_.*.sql$" }
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

function get-migration-fullpath($migration)
{

    return [io.path]::combine($solutionPath, $project, $migrationsDir, $migration.Name)
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

    $name = $name -replace $timestamp+"_+(revert|data)+_"
    
    return $name
}

update-database