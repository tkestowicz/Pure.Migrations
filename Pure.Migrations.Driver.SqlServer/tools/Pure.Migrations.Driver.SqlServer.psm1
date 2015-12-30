param(
    [Parameter(Mandatory=$true)]
    $packagesPath
)

$Script:migrationsTable = "schema_versioning"

function create-command($connectionString)
{    
    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString.ConnectionString
       
    $connection.Open()

    $cmd = $connection.CreateCommand()

    $cmd.Transaction = $connection.BeginTransaction()

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


Export-ModuleMember -Function create-command, initialize-versioning, run-migration, import-data, revert-migration, read-queries