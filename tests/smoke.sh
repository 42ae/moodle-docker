#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:?usage: smoke.sh IMAGE MOODLE_VERSION DOCUMENT_ROOT}"
expected_version="${2:?usage: smoke.sh IMAGE MOODLE_VERSION DOCUMENT_ROOT}"
expected_document_root="${3:?usage: smoke.sh IMAGE MOODLE_VERSION DOCUMENT_ROOT}"

suffix="$(date +%s)-$$"
network="moodle-smoke-${suffix}"
database="moodle-smoke-db-${suffix}"
web="moodle-smoke-web-${suffix}"
cron="moodle-smoke-cron-${suffix}"
data_volume="moodle-smoke-data-${suffix}"

cleanup() {
    docker container rm -f "$cron" "$web" "$database" >/dev/null 2>&1 || true
    docker volume rm "$data_volume" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker volume create "$data_volume" >/dev/null
docker run -d --name "$database" --network "$network" \
    -e MYSQL_ROOT_PASSWORD=root-password \
    -e MYSQL_DATABASE=moodle \
    -e MYSQL_USER=moodle \
    -e MYSQL_PASSWORD=moodle-password \
    mysql:8.4 \
    --character-set-server=utf8mb4 \
    --collation-server=utf8mb4_unicode_ci >/dev/null

for _ in $(seq 1 60); do
    if docker exec "$database" mysqladmin ping -h 127.0.0.1 -u root -proot-password --silent >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
docker exec "$database" mysqladmin ping -h 127.0.0.1 -u root -proot-password --silent >/dev/null

actual_version="$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
test "$actual_version" = "$expected_version"

docker run --rm --entrypoint test "$image" -f "${expected_document_root}/version.php"

docker image inspect "$image" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -Fx "APACHE_DOCUMENT_ROOT=${expected_document_root}" >/dev/null

docker run --rm --entrypoint sh "$image" -ec \
    'grep -R -E "^[[:space:]]*DocumentRoot[[:space:]]+${APACHE_DOCUMENT_ROOT}$" /etc/apache2/sites-enabled/* >/dev/null; apache2ctl -M 2>/dev/null | grep -q rewrite_module; test "$(php -r '\''echo ini_get("max_input_vars");'\'')" -ge 5000'

modules="$(docker run --rm --entrypoint php "$image" -m | tr '[:upper:]' '[:lower:]')"
for extension in curl dom fileinfo gd intl mbstring mysqli openssl simplexml sodium xml xmlreader zip; do
    grep -Fx "$extension" <<<"$modules" >/dev/null
done

docker run --rm -v "${data_volume}:/var/www/moodledata" "$image" true
docker run --rm --user www-data --network "$network" \
    -v "${data_volume}:/var/www/moodledata" \
    "$image" php admin/cli/install.php \
    --non-interactive \
    --agree-license \
    --lang=en \
    --wwwroot=http://localhost \
    --dataroot=/var/www/moodledata \
    --dbtype=mysqli \
    --dbhost="$database" \
    --dbname=moodle \
    --dbuser=moodle \
    --dbpass=moodle-password \
    --fullname="Moodle smoke test" \
    --shortname=smoke \
    --adminuser=admin \
    --adminpass='Admin-Pass123!' \
    --adminemail=admin@example.com >/dev/null

docker run --rm --user www-data -v "${data_volume}:/var/www/moodledata" \
    "$image" sh -c 'touch /var/www/moodledata/.write-test && rm /var/www/moodledata/.write-test'

docker run -d --name "$web" --network "$network" -p 127.0.0.1::80 \
    -v "${data_volume}:/var/www/moodledata" \
    -e MOODLE_DB_TYPE=mysqli \
    -e MOODLE_DB_HOST="$database" \
    -e MOODLE_DB_NAME=moodle \
    -e MOODLE_DB_USER=moodle \
    -e MOODLE_DB_PASSWORD=moodle-password \
    -e MOODLE_WWW_ROOT=http://localhost \
    "$image" >/dev/null

port="$(docker port "$web" 80/tcp | sed 's/.*://')"
for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
curl -fsS "http://127.0.0.1:${port}/" >/dev/null

docker run -d --name "$cron" --network "$network" \
    -v "${data_volume}:/var/www/moodledata" \
    -e MOODLE_DB_TYPE=mysqli \
    -e MOODLE_DB_HOST="$database" \
    -e MOODLE_DB_NAME=moodle \
    -e MOODLE_DB_USER=moodle \
    -e MOODLE_DB_PASSWORD=moodle-password \
    -e MOODLE_WWW_ROOT=http://localhost \
    -e MOODLE_CRON_INTERVAL=300 \
    "$image" moodle-cron >/dev/null

for _ in $(seq 1 60); do
    if docker logs "$cron" 2>&1 | grep -Eq 'Cron (run|script) completed correctly'; then
        break
    fi
    sleep 2
done
docker logs "$cron" 2>&1 | grep -Eq 'Cron (run|script) completed correctly'

echo "Smoke test passed for Moodle ${expected_version}."
