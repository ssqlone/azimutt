# Oracle connector

This library allows to connect to [Oracle](https://www.oracle.com/database), extract its schema and more...

It lists all schemas, tables, columns, relations and types and format them in a JSON Schema.

This library is made by [Azimutt](https://azimutt.app) to allow people to explore their Oracle database.
It's accessible through the [Desktop app](../../desktop) (soon), the [CLI](https://www.npmjs.com/package/azimutt) or even the website using the [gateway](../../gateway) server.

**Feel free to use it and even submit PR to improve it:**

- improve [Oracle queries](./src/oracle.ts) (look at `getSchema` function)

## Publish

- update `package.json` version
- update lib versions (`pnpm -w run update` + manual)
- test with `pnpm run dry-publish` and check `azimutt-connector-oracle-x.y.z.tgz` content
- launch `pnpm publish --access public`

View it on [npm](https://www.npmjs.com/package/@azimutt/connector-oracle).

## Dev

If you need to develop on multiple libs at the same time (ex: want to update a connector and try it through the CLI), depend on local libs but publish & revert before commit.

- Depend on a local lib: `pnpm add <lib>`, ex: `pnpm add @azimutt/models`
- "Publish" lib locally by building it: `pnpm run build`

## Oracle Setup

### Run in Docker

You can use the free version of Oracle Database

```bash
docker pull container-registry.oracle.com/database/free:latest
```

To launch a container, the needed configuration is the `ORACLE_PWD` of the `SYS` user. You can also map the default 1521 port to your computer.

```bash
docker run -d --name oracle -p 1521:1521 -e ORACLE_PWD=oracle container-registry.oracle.com/database/free:latest
```

To connect, you can use a jdbc driver with the URL `jdbc:oracle:thin:<user>/<password>@//localhost:1521/FREE`

### Setup a user

Create a user

```sql
CREATE USER "C##AZIMUTT" IDENTIFIED BY "azimutt";
```

Grand permissions

```sql
GRANT CONNECT, RESOURCE, DBA TO "C##AZIMUTT";
```

Update user quota on `Users` tablespace

```sql
ALTER USER "C##AZIMUTT" QUOTA UNLIMITED ON USERS;
```

### Create a table

```sql
CREATE TABLE "C##AZIMUTT"."USERS"(
    user_id NUMBER GENERATED BY DEFAULT AS IDENTITY,
    first_name VARCHAR2(50) NOT NULL,
    last_name VARCHAR2(50) NOT NULL,
    PRIMARY KEY(user_id)
);
```