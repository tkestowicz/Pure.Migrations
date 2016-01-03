# What is it?
**Pure.Migration** is an engine to generate empty `*.sql` scripts which will be executed in correct order on selected database. It is a set of powershell cmd-lets applied to [Nuget Package Manager Console](https://docs.nuget.org/consume/package-manager-console) in [Visual Studio](https://www.visualstudio.com/) which makes database schema maintanance **a lot easier**. It is based on [EntityFramework](https://github.com/aspnet/EntityFramework) solution and is written entirely in Powershell.

## Features

- Generates following files which are automatically added to selected .NET project:
 - [x] empty *.sql script where you put DDL commands
 - [x] empty *.sql revert script where you can put DDL commands which will be executed during database downgrade
 - [x] data import script (generated on demand)
- Adds following commnads to the Package Manager Console:
 - [x] `new-migration` to generate new set of scripts
 - [x] `migrate-database` to update database schema
 - [x] `revert-database` to downgrade database schema
- Multidatabase support (ADO-based access) for:
 - [x] Sql Server
 - [x] MySql
- Offers great performance
- Guarantees scripts execution in correct order when you use source code repository like Git, SVN or TFS
- Provides simple problems detection when some script is missing or database versioning is broken

## Installation

The engine is published as NuGet packages. 

To install SqlServer driver use command: ```install-package Pure.Migrations.SqlServer```

To install MySql driver use command: ```install-package Pure.Migrations.MySql```

Each driver depends on `Pure.Migrations.Core` package which will be installed automatically.

## Commands

**Create new migration**

```new-migration -name [name] -project [project] -migrationsDir [directory with migrations (default: Migrations)] [-force] [-withData]```

**Update database schema to target version**

```migrate-database -project [project] -migrationsDir [directory with migrations (default: Migrations)] -connectionStringName [connStringName] -targetMigration [migrationName] [-detailed]```

**Revert database schema to target version**

```revert-database -project [project] -migrationsDir [directory with migrations (default: Migrations)] -connectionStringName [connStringName] -targetMigration [migrationName] [-detailed]```

## TODO

- [ ] Add support for Oracle database
- [ ] Add support for PostgreSql database
- [ ] Add support for MSBuild (with no need of Visual Studio)
- [ ] Add 'squash' command which will merge a set of scripts into one
- [ ] ...

## Copyright

Copyright © 2016 Tymoteusz Kestowicz

## License

Pure.Migrations is licensed under [Apache v2.0](http://www.apache.org/licenses/LICENSE-2.0 "Read more about the Apache v2.0 license form").
