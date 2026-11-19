# Local database engine

This project needed a MySQL server without administrator rights (no MySQL service
install was possible, and Oracle's ZIP download returns HTTP 403 from this network).
The solution is **MariaDB 11.4.5, portable ZIP**, which speaks the MySQL protocol and
runs the same SQL. Power BI's MySQL connector, `mysql.exe`, MySQL Workbench and
`LOAD DATA LOCAL INFILE` all work unchanged.

## What was set up

```
tools/mariadb-11.4.5-winx64/
├── bin/           mysqld.exe, mysql.exe, mysqladmin.exe ...
└── data/          initialised data directory
    └── my.ini     port 3307, local_infile=1, utf8mb4
```

| Setting | Value |
| --- | --- |
| Host | 127.0.0.1 |
| Port | 3307 (3306 left free for any future MySQL install) |
| User | root |
| Password | root |
| Database | ecommerce_analytics |

## Recreate the engine from scratch

```powershell
# 1. download the portable build
Invoke-WebRequest `
  -Uri 'https://archive.mariadb.org/mariadb-11.4.5/winx64-packages/mariadb-11.4.5-winx64.zip' `
  -OutFile tools\mariadb.zip
Expand-Archive tools\mariadb.zip -DestinationPath tools

# 2. initialise the data directory with the root password "root"
tools\mariadb-11.4.5-winx64\bin\mysql_install_db.exe `
  --datadir=tools\mariadb-11.4.5-winx64\data --password=root --port=3307

# 3. replace data\my.ini with
#    [mysqld]
#    datadir=.../data
#    port=3307
#    bind-address=127.0.0.1
#    local_infile=1
#    character-set-server=utf8mb4
#    collation-server=utf8mb4_general_ci

# 4. start / stop
powershell -File tools\start_db.ps1
powershell -File tools\stop_db.ps1
```

The server does **not** start automatically after a reboot. Run `tools/start_db.ps1`
before opening Power BI or the SQL client.

## Equivalent MySQL 8 command

On a machine with MySQL Server 8.0 installed, the same project works with:

```powershell
mysql -u root -p < sql\00_create_database.sql
mysql --local-infile=1 -u root -p < sql\01_load_data.sql
```

and Power BI connects on port 3306 with the same views.
