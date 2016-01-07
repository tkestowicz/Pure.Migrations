param(
    [Parameter(Mandatory=$true)]
    $driver,
    [Parameter(Mandatory=$true)]
    $project
)

Import-Module $driver -ArgumentList @($packagesPath, $project) -Force -DisableNameChecking

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