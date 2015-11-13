﻿#todo: poprawić ścieżke
Add-Type -Path "D:\Projects\planit\PlanIt\packages\MySql.Data.6.9.7\lib\net45\MySql.Data.dll"

Import-Module $PSScriptRoot\Pure.Migrations.Driver.Core.psm1 -Force -DisableNameChecking

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

Export-ModuleMember -Function create-command, initialize-versioning, run-migration, import-data, revert-migration