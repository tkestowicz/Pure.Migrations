﻿
function execute-script($file, $cmd, $verbose)
{
    $queries = read-queries $file

    print-verbose-header $verbose

    foreach($query in $queries)
    {
        if($query.Length -gt 0)
        {
            print-verbose $query $verbose  

            $cmd.CommandText = $query
            $rows = $cmd.ExecuteNonQuery()          
        }    
    }

    print-verbose-footer $verbose
}

function import-data($file, $cmd, $verbose)
{
    execute-script $file $cmd $verbose
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

function print-verbose-header($verbose)
{
    if($verbose)
    {
        Write-Host
        Write-Host "---------start---------" -ForegroundColor Gray
    }
}

function print-verbose-footer($verbose)
{
    if($verbose)
    {
        Write-Host
        Write-Host "---------end---------" -ForegroundColor Gray
        Write-Host
    }
}

function print-verbose($text, $verbose)
{
    if($verbose)
    {
        Write-Host
        Write-Host $text -ForegroundColor Gray
    }     
}

Export-ModuleMember -Function execute-script, import-data