# Supported tags and respective `Dockerfile` links
* [`latest`, `3.6` (3.6/Dockerfile)](https://github.com/liyali/moodle-docker/blob/master/3.x/Dockerfile)

# Quick reference
* **Github:**
https://github.com/liyali/moodle-docker/issues
* **Maintained by:**
Alexandre Esser
* **Moodle docs:**
https://docs.moodle.org/



This image is inspired by the official Wordpress image available on Docker Hub.

## What is Moodle?

![Moodle](https://moodle.org/logo/moodle-logo.png "Moodle logo")

Moodle is a learning platform designed to provide educators, administrators and learners with a single robust, secure and integrated system to create personalised learning environments.
Moodle is built by the Moodle project which is led and coordinated by Moodle HQ, an Australian company of 30 developers which is financially supported by a network of over 60 Moodle Partner service companies worldwide.

## How to use this image?

# Getting started

First, create a new network for the application and the database:
`$ docker network create moodle`

Then, start a new database process in an isolated container:
`$ docker run --name mysql --network moodle -e MYSQL_ROOT_PASSWORD=password -d mysql`

Finally, you can run this moodle image and link it to your mysql container:
`$ docker run --name my-moodle  --network moodle --link mysql:database -p 8080:80 -d aesr/moodle`

Access it via `http://localhost:8080` or `http://host-ip:8080` in a browser.

# Prerequisites

To run this application you need Docker Engine 1.10+. Docker Compose is recommended with a version 2 or later.

# Environment variables

Variable | Default | Description
--- | --- | ---
*MOODLE_DB_HOST* | `database` an alias on the linked mysql container | **Set the database host**
*MOODLE_DB_PORT* | `3306` | **Set the database host port**
*MOODLE_DB_NAME* | `moodle` | **Set the database name**
*MOODLE_DB_USER* | `root` | **Set the database user**
*MOODLE_DB_PASSWORD* | `''` or `$MYSQL_ENV_MYSQL_ROOT_PASSWORD` | **Set the database password**
*MOODLE_WWW_ROOT* | `''` | **Set the moodle URL**
*MOODLE_DATA_ROOT* | `'/var/www/moodledata'` | **Path where Moodle can save uploaded files**

## Run the application using `docker-compose`

```
# Example docker-compose.yml
version: '3'
services:
  db:
    image: mysql
    volumes:
      - db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: moodle
      MYSQL_USER: moodle
      MYSQL_PASSWORD: password
    restart: always
  moodle:
    image: aesr/moodle
    ports:
      - "8080:80"
    links:
      - db:database
    volumes:
      - ./moodledata:/var/www/moodledata
      - ./moodle:/var/www/html
    restart: always
    environment:
      MOODLE_DB_HOST: database
      MOODLE_DB_PORT: 3306
      MOODLE_DB_NAME: moodle
      MOODLE_DB_USER: moodle
      MOODLE_DB_PASSWORD: password
      MOODLE_WWW_ROOT: ${MOODLE_WWW_ROOT:-http://localhost:8080}
      MOODLE_DATA_ROOT: /var/www/moodledata
    labels:
      cron.moodle.command: "/usr/local/bin/php /var/www/html/admin/cli/cron.php"
      cron.moodle.interval: "every minute"
  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    ports:
      - "8081:80"
    links:
      - db:database
    environment:
      PMA_HOST: database
  tasks:
    image: funkyfuture/deck-chores
    restart: unless-stopped
    environment:
      TIMEZONE: Europe/Paris
      LABEL_NAMESPACE: cron
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
volumes:
    db_data:
      driver: local
```


In order to get the above `docker-compose.yml` up and running, run the command below:

`$ docker-compose up -d`

# Docker Compose breakdown

Launching this docker compose file will run four isolated service containers: **MySQL, Moodle, PhpMyAdmin and cron**.

* __Data Volumes__
We are mounting two host directories as data volumes to handle moodle data as well as moodle core. MySQL data is mounted as a named volume in order to persist the data.

* __Moodle__
The image `Dockerfile` is exposing the `port 80` on the container, you can change the port mapping on the host by changing the port variable of the _moodle_ service.
Refer to the section _Environment variables_ above for more information about moodle environment variables.

* __Cron jobs__

The Moodle `cron` process is a PHP script (part of the standard Moodle installation) that must be run regularly in the background. The Moodle cron script runs different tasks at differently scheduled intervals.

In order to run cron, we use the useful [funkyfuture/deck-chores](https://hub.docker.com/r/funkyfuture/deck-chores/) image which allows us to define regular cron jobs to run within a container context via container labels.

````
    labels:
      cron.moodle.command: "/usr/local/bin/php /var/www/html/admin/cli/cron.php"
      cron.moodle.interval: "every minute"
````

## Adding additional libraries / extensions

This image does not provide any additional PHP extensions or other libraries, even if they are required by popular plugins. There are an infinite number of possible plugins, and they potentially require any extension PHP supports. Including every PHP extension that exists would dramatically increase the image size.

If you need additional PHP extensions, you'll need to create your own image using `FROM aesr/moodle`. The [documentation of the php image](https://github.com/docker-library/docs/blob/master/php/README.md#how-to-install-more-php-extensions) explains how to compile additional extensions.
