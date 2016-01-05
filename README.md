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

```new-migration -name <string> -project <string> [-migrationsDir <string>] [-force] [-withData]```

 Option                   | Description
--------------------------|--------------------------
`-name <string>`          | Specifies the name of the custom script. 
`-project <string>`       | Specifies the Visual Studio project where the scripts will be created. 
`-migrationsDir <string>` | Specifies the name of the directory in the selected project that contains all <br> migration scripts. If ommited, the directory will be named "**Migrations**".
`-force`                  | Overwrites all custom scripts with provided name. 
`-withData`               | Generates separate script for data import (seed script). 

**Update database schema to target version**

```migrate-database -project <string> [-migrationsDir <string>] [-connectionStringName <string>] [-targetMigration <string>] [-detailed]```

 Option                          | Description
---------------------------------|---------------------------------
`-project <string>`              | Specifies the Visual Studio project where the migration scripts are located. 
`-migrationsDir <string>`        | Specifies the name of the directory in the selected project that contains all <br> migration scripts. If ommited, the directory will be named "**Migrations**".
`-connectionStringName <string>` | Specifies the name of a connection string to use from the application’s <br> configuration file located in a Visual Studio project which is set as `startup` project.
`-targetMigration <string>`      | Specifies the name of a particular script to update the database to. <br>If ommited, all scripts will be executed.
`-detailed`                      | Writes detailed (verbose) information about command execution to the console. 

**Revert database schema to target version**

```revert-database -project <string> [-migrationsDir <string>] [-connectionStringName <string>] [-targetMigration <string>] [-detailed]```

 Option                          | Description
---------------------------------|---------------------------------
`-project <string>`              | Specifies the Visual Studio project where the migration scripts are located. 
`-migrationsDir <string>`        | Specifies the name of the directory in the selected project that contains all <br> migration scripts. If ommited, the directory will be named "**Migrations**".
`-connectionStringName <string>` | Specifies the name of a connection string to use from the application’s <br> configuration file located in a Visual Studio project which is set as `startup` project.
`-targetMigration <string>`      | Specifies the name of a particular script to update the database to. <br>If ommited, all scripts will be executed.
`-detailed`                      | Writes detailed (verbose) information about command execution to the console. 

## Error messages explanations

The table below contains error messages with explanations which you can see while using the engine. Only not self-explanatory messages were described.

Message | Explanation
---------|-----------
*Database cannot be reverted to '`migration name`' migration. Inconsistency detected between migrations and current schema version.* | Occurs when *SchemaVersion* table in the database is corrupted or some scripts on a disk are missing (only `revert-database` command).
*Migration '`migration name`' cannot be applied because newer migration has been already applied.*| Occurs when your database has newer script or scripts applied (only `migrate-database` command). <br>**Example:** *you work on a branch A and create a bunch of scripts. Then you switch to branch B, create some other scripts and apply them to the database. Next you switch back to branch A and try to apply older scripts what is not possible.*
*You are trying to revert database to the oldest migration which is not possible.* | Occurs when you will specify first script as a `-targetMigration` (only `revert-database` command).

## TODO

- [ ] Add support for Oracle database
- [ ] Add support for PostgreSql database
- [ ] Add support for MSBuild (with no need of Visual Studio)
- [ ] Add 'squash' command which will merge a set of scripts into one
- [ ] Add '-startupProject' parameter
- [ ] ...

## Copyright

Copyright © 2016 Tymoteusz Kestowicz

## License

Pure.Migrations is licensed under [Apache v2.0](http://www.apache.org/licenses/LICENSE-2.0 "Read more about the Apache v2.0 license form").
