param(
    [Parameter(Mandatory=$true)]
    $packagesPath,
    [Parameter(Mandatory=$true)]
    $project
)

$mysqlDirectory = [System.IO.Directory]::EnumerateDirectories($packagesPath, "MySql.Data*") | Sort-Object Name -Descending | Select-Object -First 1

$dotNetVersion = detect-framework-version
Write-Host "lib\$dotNetVersion\MySql.Data.dll"
$mysqlLibPath = Join-Path $mysqlDirectory "lib\$dotNetVersion\MySql.Data.dll"

Add-Type -Path $mysqlLibPath

$Script:migrationsTable = "schema_versioning"

function create-command($connectionString)
{    
    $connection = New-Object MySql.Data.MySqlClient.MySqlConnection $connectionString.ConnectionString
       
    $connection.Open()

    $cmd = $connection.CreateCommand()

    $cmd.Transaction = $connection.BeginTransaction()
    $cmd.CommandText = "SET autocommit = 0"

    $rows = $cmd.ExecuteNonQuery()

    return $cmd
}

function enable-versioning($command)
{        
    $command.CommandText = "CREATE TABLE IF NOT EXISTS $Script:migrationsTable (
                                Id BIGINT UNSIGNED PRIMARY KEY, 
                                Migration VARCHAR(150) NOT NULL, 
                                CreatedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                            )"
                        
    $rows = $command.ExecuteNonQuery()
}

function initialize-versioning($command)
{
    enable-versioning $command

    $result = get-applied-migrations $command

    return $result
}

function get-applied-migrations($command)
{
    $command.CommandText = "select id from $Script:migrationsTable order by id desc"
    $reader = $command.ExecuteReader()

    while($reader.Read())
    {
        $reader.GetValue($1)
    }
    $reader.Close()
}

function run-migration($file, $migrationId, $cmd, $verbose)
{
    execute-script $file $cmd $verbose

    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    
    $cmd.CommandText = "insert into $Script:migrationsTable(id, migration) values($migrationId, '$name')"

    $rows = $cmd.ExecuteNonQuery()
}

function revert-migration($file, $migrationId, $cmd, $verbose)
{
    execute-script $file $cmd $verbose

    $cmd.CommandText = "delete from $Script:migrationsTable where id = $migrationId"

    $rows = $cmd.ExecuteNonQuery()
}

function read-queries($file)
{
    $lines = get-content $file.FullName

    $command = ""
    foreach($line in $lines)
    {
        $command = $command+$line
        if($line.EndsWith(";"))
        {
            $command
            $command = ""
        }
    }
}

function detect-framework-version()
{
    $version = ($project.Properties | where { $_.Name -eq "TargetFrameworkMoniker" } | select -first 1).Value
    Write-Host $version
    if($version -match "4.0"){
        
        return "net40"
    }
    elseif($version -match "4.[1-9]"){
        
        return "net45"
    }
    else{
        return "net20"
    }
}


Export-ModuleMember -Function create-command, initialize-versioning, run-migration, import-data, revert-migration, read-queries