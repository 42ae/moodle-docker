FROM php:5.6-apache

# based on official image release from docker
MAINTAINER Alexandre Esser <alexandre@esser.fr>

# install the PHP extensions we need
RUN set -ex; \
  \
  apt-get update; \
  apt-get install -y \
    libicu-dev \
    libpng-dev \
    libxml2-dev \
    zlib1g-dev \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  \
  docker-php-ext-install gd mysqli opcache xmlrpc intl soap zip

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
# see https://docs.moodle.org/33/en/OPcache
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'opcache.use_cwd=1'; \
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.enable_file_override=0'; \
    echo 'opcache.enable_file_override=0'; \
    echo '; If something does not work in Moodle'; \
    echo ';opcache.revalidate_path = 1 ; May fix problems with include paths'; \
    echo '; Experimental for Moodle 2.6 and later'; \
    echo ';opcache.fast_shutdown = 1'; \
    echo ';opcache.enable_cli = 1 ; Speeds up CLI cron'; \
    echo ';opcache.load_comments = 0 ; May lower memory use, might not be compatible with add-ons and other apps.'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN a2enmod rewrite expires

VOLUME ["/var/www/html", "/var/www/moodledata"]

ENV MOODLE_BRANCH 33
ENV MOODLE_RELEASE 3.3
ENV MOODLE_SHA1 cd740701f5f01bb1469a0f96307739fee5b28863

RUN set -ex; \
  curl -o moodle.tgz -fSL "https://download.moodle.org/stable${MOODLE_BRANCH}/moodle-${MOODLE_RELEASE}.tgz"; \
  echo "$MOODLE_SHA1 moodle.tgz" | sha1sum -c -; \
# upstream tarballs include ./moodle/ so this gives us /usr/src/moodle
  tar -xzf moodle.tgz -C /usr/src/; \
  rm moodle.tgz; \
  chown -R www-data:www-data /usr/src/moodle

COPY docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]