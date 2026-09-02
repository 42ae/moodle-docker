ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-apache

ARG MOODLE_VERSION=5.2.2
ARG MOODLE_BRANCH=502
ARG MOODLE_SHA256=72be209e7c0f5341b87de0bc993b2430087fda2769d8c3cc2f32736d1513e88c
ARG MOODLE_DOCUMENT_ROOT=/var/www/html/public

LABEL org.opencontainers.image.title="Moodle LMS" \
      org.opencontainers.image.description="Versioned Moodle LMS images for Docker" \
      org.opencontainers.image.source="https://github.com/42ae/moodle-docker" \
      org.opencontainers.image.url="https://github.com/42ae/moodle-docker" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.version="${MOODLE_VERSION}"

ENV APACHE_DOCUMENT_ROOT="${MOODLE_DOCUMENT_ROOT}" \
    MOODLE_VERSION="${MOODLE_VERSION}"

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libonig-dev \
        libpng-dev \
        libwebp-dev \
        libxml2-dev \
        libzip-dev \
    ; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" exif gd intl mbstring mysqli opcache soap zip; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual ${savedAptMark}; \
    find "$(php -r 'echo ini_get("extension_dir");')" -type f -name '*.so' -exec ldd '{}' ';' \
        | awk '/=>/ { library = $(NF-1); if (index(library, "/usr/local/") == 1) next; gsub("^/(usr/)?", "", library); print library }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    php -r '$required = ["curl", "dom", "fileinfo", "gd", "intl", "mbstring", "mysqli", "openssl", "simplexml", "sodium", "xml", "xmlreader", "zip"]; foreach ($required as $extension) { if (!extension_loaded($extension)) { fwrite(STDERR, "Missing PHP extension: {$extension}\n"); exit(1); } } if (PHP_INT_SIZE !== 8) { fwrite(STDERR, "A 64-bit PHP build is required.\n"); exit(1); }'

RUN set -eux; \
    a2enmod expires headers rewrite; \
    sed -ri "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf; \
    { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.max_accelerated_files=10000'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.use_cwd=1'; \
        echo 'opcache.validate_timestamps=1'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.enable_file_override=0'; \
        echo 'max_input_vars=5000'; \
        echo 'memory_limit=256M'; \
        echo 'upload_max_filesize=100M'; \
        echo 'post_max_size=100M'; \
    } > /usr/local/etc/php/conf.d/moodle-recommended.ini

RUN set -eux; \
    curl -fsSL -o /tmp/moodle.tgz "https://packaging.moodle.org/stable${MOODLE_BRANCH}/moodle-${MOODLE_VERSION}.tgz"; \
    echo "${MOODLE_SHA256}  /tmp/moodle.tgz" | sha256sum -c -; \
    tar -xzf /tmp/moodle.tgz -C /var/www/html --strip-components=1; \
    rm /tmp/moodle.tgz; \
    mkdir -p /var/www/moodledata; \
    chown -R www-data:www-data /var/www/html /var/www/moodledata; \
    chmod 0750 /var/www/moodledata; \
    test -f "${APACHE_DOCUMENT_ROOT}/version.php"; \
    test -f "${APACHE_DOCUMENT_ROOT}/index.php"

COPY docker/docker-config.php /usr/local/bin/docker-moodle-config
COPY docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
    && chmod 0644 /usr/local/bin/docker-moodle-config

WORKDIR /var/www/html
VOLUME ["/var/www/moodledata"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -fsS http://localhost/ > /dev/null || exit 1
