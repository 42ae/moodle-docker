#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 4 ]; then
    echo >&2 'usage: upgrade.sh IMAGE_3_11 IMAGE_4_1 IMAGE_4_5 IMAGE_5_2'
    exit 2
fi

images=("$@")
suffix="$(date +%s)-$$"
network="moodle-upgrade-${suffix}"
database="moodle-upgrade-db-${suffix}"
web="moodle-upgrade-web-${suffix}"
data_volume="moodle-upgrade-data-${suffix}"

cleanup() {
    docker container rm -f "$web" "$database" >/dev/null 2>&1 || true
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

docker run --rm -v "${data_volume}:/var/www/moodledata" "${images[0]}" true
docker run --rm --user www-data --network "$network" \
    -v "${data_volume}:/var/www/moodledata" \
    "${images[0]}" php admin/cli/install.php \
    --non-interactive --agree-license --lang=en \
    --wwwroot=http://localhost --dataroot=/var/www/moodledata \
    --dbtype=mysqli --dbhost="$database" --dbname=moodle \
    --dbuser=moodle --dbpass=moodle-password \
    --fullname="Moodle upgrade test" --shortname=upgrade \
    --adminuser=admin --adminpass='Admin-Pass123!' \
    --adminemail=admin@example.com >/dev/null

for image in "${images[@]:1}"; do
    docker run --rm --user www-data --network "$network" \
        -v "${data_volume}:/var/www/moodledata" \
        -e MOODLE_DB_TYPE=mysqli \
        -e MOODLE_DB_HOST="$database" \
        -e MOODLE_DB_NAME=moodle \
        -e MOODLE_DB_USER=moodle \
        -e MOODLE_DB_PASSWORD=moodle-password \
        -e MOODLE_WWW_ROOT=http://localhost \
        "$image" php admin/cli/upgrade.php --non-interactive >/dev/null
done

docker run -d --name "$web" --network "$network" -p 127.0.0.1::80 \
    -v "${data_volume}:/var/www/moodledata" \
    -e MOODLE_DB_TYPE=mysqli \
    -e MOODLE_DB_HOST="$database" \
    -e MOODLE_DB_NAME=moodle \
    -e MOODLE_DB_USER=moodle \
    -e MOODLE_DB_PASSWORD=moodle-password \
    -e MOODLE_WWW_ROOT=http://localhost \
    "${images[3]}" >/dev/null

port="$(docker port "$web" 80/tcp | sed 's/.*://')"
for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
curl -fsS "http://127.0.0.1:${port}/" >/dev/null

docker run --rm --user www-data --network "$network" \
    -v "${data_volume}:/var/www/moodledata" \
    -e MOODLE_DB_TYPE=mysqli \
    -e MOODLE_DB_HOST="$database" \
    -e MOODLE_DB_NAME=moodle \
    -e MOODLE_DB_USER=moodle \
    -e MOODLE_DB_PASSWORD=moodle-password \
    -e MOODLE_WWW_ROOT=http://localhost \
    "${images[3]}" php admin/cli/cron.php --keep-alive=0 >/dev/null

echo 'Upgrade test passed: 3.11 -> 4.1 -> 4.5 -> 5.2.'
