if (Get-Module | ?{ $_.Name -eq 'Pure.Migrations.Driver.MySql' })
{
    Remove-Module Pure.Migrations.Driver.MySql
}