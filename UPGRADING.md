# Upgrading Moodle

Moodle database upgrades are one-way. Never run an older Moodle image against a database that a newer version has upgraded, and never attempt a downgrade by changing `MOODLE_VERSION`.

## Supported legacy upgrade path

This repository tests the required sequence:

```text
3.11.18 -> 4.1.22 -> 4.5.13 -> 5.2.2
```

Do not skip the intermediate versions. Moodle 3.11 and 4.1 images exist only to make this migration possible.

## Before every step

1. Read the target release notes and verify that the server and every installed plugin or theme support the target Moodle and PHP versions.
2. Test the complete upgrade on a copy of production first.
3. Put the site in maintenance mode.
4. Back up the database, `moodledata`, custom code, and the current configuration.
5. Verify that the backups can be restored before changing the image.

Example backups for the supplied Compose stack:

```console
mkdir -p backups
docker compose exec -T database sh -c \
  'exec mysqldump --single-transaction --default-character-set=utf8mb4 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  > backups/moodle.sql
docker run --rm \
  -v moodle-docker_moodle_data:/source:ro \
  -v "$PWD/backups:/backup" \
  alpine tar -C /source -czf /backup/moodledata.tar.gz .
```

The Compose project name determines the volume name; confirm it with `docker volume ls` before using the example.

## Upgrade one release

Start from a full version tag, not a floating series tag. Repeat these steps for each arrow in the supported path.

```console
docker compose exec --user www-data moodle php admin/cli/maintenance.php --enable
```

Set the next full version in `.env`, for example:

```dotenv
MOODLE_VERSION=4.1.22
```

Then replace the application and cron containers, run the database migration, and validate the site:

```console
docker compose pull moodle cron
docker compose up -d --no-deps moodle
docker compose exec --user www-data moodle php admin/cli/upgrade.php --non-interactive
docker compose up -d --no-deps cron
docker compose exec --user www-data moodle php admin/cli/cron.php
docker compose ps
docker compose exec --user www-data moodle php admin/cli/maintenance.php --disable
```

Check the web UI, logs, background tasks, authentication, file access, and representative courses before continuing to the next release. Take a new backup after each successful step.

## Migrating from the old repository layout

The former Compose file mounted Moodle core from `./moodle` and used an unversioned image. Do not carry that core-code mount into the new stack.

1. Pin the running legacy application to `aesr/moodle:3.11` before any pull.
2. Export a logical database dump and archive the old `moodledata` directory.
3. Copy custom plugins and themes into a derived image based on the exact target version; do not copy old Moodle core.
4. Restore the database and `moodledata` into clean named volumes in a separate test project.
5. Complete and validate the full staged upgrade before replacing production.

## Recovery

If a step fails, preserve its logs and stop the new containers. Restore both the database and `moodledata` from the backup taken immediately before that step into clean volumes, then restart the previously pinned image. Do not point the old image at a partially upgraded database.
