# Moodle Docker

[![Docker images](https://github.com/42ae/moodle-docker/actions/workflows/docker.yml/badge.svg)](https://github.com/42ae/moodle-docker/actions/workflows/docker.yml)

![Moodle](assets/moodle-logo.png "Moodle logo")

Versioned, multi-architecture Moodle images for local development and self-hosted deployments. Images are published to [GitHub Container Registry](https://github.com/42ae/moodle-docker/pkgs/container/moodle) and [Docker Hub](https://hub.docker.com/r/aesr/moodle).

> [!CAUTION]
> The `latest` tag now tracks Moodle 5.2, not the historical Moodle 3.x image. Existing installations must pin `3.11` before pulling, or follow the [staged upgrade guide](UPGRADING.md). Never upgrade a production database without a tested backup and plugin-compatibility review.

## Available versions

| Moodle | PHP | Status | Tags |
|---|---:|---|---|
| 3.11.18 | 8.0 | Legacy/EOL; upgrade compatibility only | `3.11.18`, `3.11`, `3`, `legacy-3.11` |
| 4.1.22 | 8.1 | Legacy/EOL; upgrade bridge only | `4.1.22`, `4.1`, `legacy-4.1` |
| 4.5.13 | 8.3 | LTS, security fixes | `4.5.13`, `4.5`, `4`, `lts` |
| 5.2.2 | 8.4 | Current stable | `5.2.2`, `5.2`, `5`, `latest` |

Use a full version tag for reproducible production deployments. Series tags are convenient but can move to newer point releases after rebuilds.

## Quick start

```console
cp .env.example .env
# Replace every example password in .env before exposing this stack.
docker compose up -d
```

Open <http://localhost:8080>. The first visit starts Moodle's web installer. The Compose stack includes MySQL 8.4 and a separate Moodle cron service; phpMyAdmin is optional:

```console
docker compose --profile tools up -d
```

### Choose a Moodle version

Set `MOODLE_VERSION` in `.env`, then pull and start the stack:

```dotenv
MOODLE_VERSION=4.5
```

```console
docker compose pull
docker compose up -d
```

Supported choices include `3.11`, `4.1`, `4.5`, and `5.2`. Changing the value on an existing installation is an upgrade, not a downgrade or a fresh selection; follow [UPGRADING.md](UPGRADING.md).

GitHub Container Registry is the default. To use Docker Hub instead:

```dotenv
MOODLE_IMAGE=aesr/moodle
```

## Configuration

The image supports the following environment variables. If any Moodle configuration variable is provided and `config.php` is absent, the entrypoint creates a minimal cross-version configuration file.

| Variable | Default | Purpose |
|---|---|---|
| `MOODLE_DB_HOST` | `database` | MySQL/MariaDB hostname |
| `MOODLE_DB_PORT` | `3306` | Database port |
| `MOODLE_DB_NAME` | `moodle` | Database name |
| `MOODLE_DB_USER` | `moodle` | Database user |
| `MOODLE_DB_PASSWORD` | empty | Database password |
| `MOODLE_DB_PREFIX` | `mdl_` | Table prefix |
| `MOODLE_WWW_ROOT` | `http://localhost:8080` | Public Moodle URL |
| `MOODLE_DATA_ROOT` | `/var/www/moodledata` | Private writable data directory |
| `MOODLE_REVERSE_PROXY` | `false` | Trust a reverse proxy |
| `MOODLE_SSL_PROXY` | `false` | TLS terminates at a trusted proxy |
| `MOODLE_CRON_INTERVAL` | `60` | Cron-sidecar interval in seconds |

Every variable also accepts Docker secret syntax through a matching `_FILE` variable, such as `MOODLE_DB_PASSWORD_FILE=/run/secrets/moodle_db_password`. Do not set both forms for the same variable.

The entrypoint configures Moodle; it deliberately does not create databases. Provision the database separately or use the included Compose stack.

## Persistence and backups

Only database data and `moodledata` are persisted by the supplied Compose file:

- `db_data` stores MySQL files.
- `moodle_data` stores uploads, caches, and generated application data.

Moodle core remains inside the immutable image. Do not mount a volume over `/var/www/html`; doing so hides the versioned code and makes upgrades difficult to reproduce. Back up both the database and `moodledata`, and test restores regularly. See [UPGRADING.md](UPGRADING.md) for example backup and upgrade commands.

## Plugins, themes, and extra PHP extensions

For repeatable deployments, build a derived image and pin its base to a full version:

```dockerfile
FROM ghcr.io/42ae/moodle:5.2.2

COPY --chown=www-data:www-data local/myplugin/ /var/www/html/local/myplugin/
COPY --chown=www-data:www-data theme/mytheme/ /var/www/html/theme/mytheme/
```

Targeted read-only mounts can be useful for local development, but a derived image is safer for production. Install additional PHP extensions in the derived image when a plugin requires them.

## Operations

Run a one-off Moodle CLI command with the web service:

```console
docker compose exec --user www-data moodle php admin/cli/maintenance.php --enable
docker compose exec --user www-data moodle php admin/cli/upgrade.php --non-interactive
docker compose exec --user www-data moodle php admin/cli/maintenance.php --disable
```

The `cron` service runs `admin/cli/cron.php` continuously at `MOODLE_CRON_INTERVAL`. To run cron once:

```console
docker compose exec --user www-data moodle php admin/cli/cron.php
```

## Build locally

Version metadata and verified upstream SHA-256 values live in [`versions.json`](versions.json). For example:

```console
docker build \
  --build-arg MOODLE_VERSION=5.2.2 \
  --build-arg PHP_VERSION=8.4 \
  --build-arg MOODLE_BRANCH=502 \
  --build-arg MOODLE_SHA256=72be209e7c0f5341b87de0bc993b2430087fda2769d8c3cc2f32736d1513e88c \
  --build-arg APACHE_DOCUMENT_ROOT=/var/www/html/public \
  -t moodle:local .
```

## Security and support

- Moodle 3.11 and 4.1 are unsupported upstream and are published only for compatibility and staged upgrades.
- Prefer the supported 4.5 LTS or current 5.2 series for new deployments.
- Terminate TLS at a trusted proxy, keep the database off public networks, use secrets instead of committed passwords, and restrict access to `moodledata`.
- Review [Moodle security announcements](https://moodle.org/security/) and rebuild derived images regularly.

Issues and contributions are welcome in the [42ae/moodle-docker repository](https://github.com/42ae/moodle-docker).
