param(
    [Parameter(Mandatory=$true)]
    $packagesPath,
    [Parameter(Mandatory=$true)]
    $project
)

$Script:migrationsSchema = "PureMigrations"
$Script:migrationsTable = "SchemaVersioning"

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
    $command.CommandText = "IF NOT EXISTS( SELECT s.name, t.name FROM sys.tables as t INNER JOIN sys.schemas as s on t.schema_id=s.schema_id WHERE t.name = '$Script:migrationsTable' AND s.name = '$Script:migrationsSchema')
                            BEGIN
	                            	EXEC('CREATE SCHEMA $Script:migrationsSchema')
	                                CREATE TABLE [$Script:migrationsSchema].[$Script:migrationsTable] (
									    Id BIGINT PRIMARY KEY, 
									    Migration VARCHAR(200) NOT NULL, 
									    CreatedAt DATETIME2 NOT NULL DEFAULT GETDATE()
								    )
                            END"
                        
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
    $command.CommandText = "SELECT Id FROM [$Script:migrationsSchema].[$Script:migrationsTable] ORDER BY Id DESC"
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
    
    $cmd.CommandText = "INSERT INTO [$Script:migrationsSchema].[$Script:migrationsTable](Id, Migration) VALUES($migrationId, '$name')"

    $rows = $cmd.ExecuteNonQuery()
}

function revert-migration($file, $migrationId, $cmd, $verbose)
{
    execute-script $file $cmd $verbose

    $cmd.CommandText = "DELETE FROM [$Script:migrationsSchema].[$Script:migrationsTable] WHERE Id = $migrationId"

    $rows = $cmd.ExecuteNonQuery()
}


function read-queries($file)
{
    $script = [System.Io.File]::ReadAllText($file.FullName)

    $options = [System.Text.RegularExpressions.RegexOptions] "Multiline, IgnorePatternWhitespace, IgnoreCase"
    
    $statements = [System.Text.RegularExpressions.Regex]::Split($script, "^\s*GO\s* ($ | \-\- .*$)", $options)

    $commands = $statements | Where { [string]::IsNullOrWhiteSpace($_) -eq $False }

    foreach($command in $commands)
    {
        $command.Trim("\r").Trim("\n").Trim()
    }
}


Export-ModuleMember -Function create-command, initialize-versioning, run-migration, import-data, revert-migration, read-queries