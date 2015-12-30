if (Get-Module | ?{ $_.Name -eq 'Pure.Migrations.Driver.SqlServer' })
{
    Remove-Module Pure.Migrations.Driver.SqlServer
}