if (Get-Module | ?{ $_.Name -eq 'Pure.Migrations.Core' })
{
    Remove-Module Pure.Migrations.Core
}

if (Get-Module | ?{ $_.Name -eq 'Pure.Migrations.Driver.Core' })
{
    Remove-Module Pure.Migrations.Driver.Core
}