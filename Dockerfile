# syntax=docker/dockerfile:1.3

FROM php:8.4-fpm-alpine
RUN set -ex; \
    \
    export CFLAGS="${PHP_CFLAGS:?}"; \
    export CPPFLAGS="${PHP_CPPFLAGS:?}"; \
    export LDFLAGS="${PHP_LDFLAGS:?} -Wl,--strip-all"; \
    \
    # Runtime dependencies
    apk add --no-cache \
        c-client \
        icu \
        libintl \
        libpng \
        libzip \
        msmtp \
        nginx \
        openldap \
        runit \
        openssl \
        linux-headers \
    ; \
    \
    # Build dependencies
    apk add --no-cache --virtual .build-deps \
        ${PHPIZE_DEPS} \
        gettext-dev \
        icu-dev \
        imap-dev \
        krb5-dev \
        libpng-dev \
        libzip-dev \
        openldap-dev \
        openssl-dev \
    ; \
    \
    # Install PHP extensions
    docker-php-ext-install -j "$(nproc)" \
        gd \
        gettext \
        intl \
        ldap \
        mysqli \
        sockets \
        zip \
    ; \
    pecl install apcu; \
    pecl install imap; \
    docker-php-ext-enable \
        apcu \
        opcache \
        imap \
    ; \
    \
    # Create msmtp log
    touch /var/log/msmtp.log; \
    chown www-data:www-data /var/log/msmtp.log; \
    \
    # Create data dir
    mkdir /var/lib/osticket; \
    \
    # Clean up
    apk del .build-deps; \
    rm -rf /tmp/pear /var/cache/apk/*
# DO NOT FORGET TO CHECK THE LANGUAGE PACK DOWNLOAD URL BELOW
# DO NOT FORGET TO UPDATE "image-version" FILE
ENV OSTICKET_VERSION=1.18.3 \
    OSTICKET_SHA256SUM=f61b672c3ecf47a3e546fab8c9e2206ca7b33f908518eda6675b269812ff0cb6
RUN --mount=type=bind,source=utils/verify-plugin.php,target=/tmp/verify-plugin.php,readonly \
    \
    set -ex; \
    \
    wget -q -O osTicket.zip https://github.com/osTicket/osTicket/releases/download/\
v${OSTICKET_VERSION}/osTicket-v${OSTICKET_VERSION}.zip; \
    echo "${OSTICKET_SHA256SUM}  osTicket.zip" | sha256sum -c; \
    unzip osTicket.zip 'upload/*'; \
    rm osTicket.zip; \
    mkdir /usr/local/src; \
    mv upload /usr/local/src/osticket; \
    # Hard link the sources to the public directory
    cp -al /usr/local/src/osticket/. /var/www/html; \
    # Hide setup
    rm -r /var/www/html/setup; \
    \
    cd /var/www/html; \
    \
    for lang in bg bn bs ca cs da de el es_AR es_ES es_MX et eu fa fi fr gl he hi hr hu id is it \
        ja ka km ko lt lv mk mn ms nl no pl pt_BR pt_PT ro ru sk sl sq sr sr_CS sv_SE sw th tr uk \
        ur_IN ur_PK vi zh_CN zh_TW; do \
        # This URL is the same as what is used by the official osTicket Downloads page. This URL is
        # used even for minor versions >= 14.
        wget -q -O /var/www/html/include/i18n/${lang}.phar \
            https://s3.amazonaws.com/downloads.osticket.com/lang/1.14.x/${lang}.phar; \
        php /tmp/verify-plugin.php "/var/www/html/include/i18n/${lang}.phar"; \
    done
RUN set -ex; \
    \
    for plugin in audit auth-2fa auth-ldap auth-oauth2 auth-passthru auth-password-policy \
        storage-fs storage-s3; do \
        wget -q -O /var/www/html/include/plugins/${plugin}.phar \
            https://s3.amazonaws.com/downloads.osticket.com/plugin/${plugin}.phar; \
    done; \
    # This checks `.phar` integrity (authenticity check is not supported - see
    # https://github.com/osTicket/osTicket/issues/6376).
    for phar in /var/www/html/include/plugins/*.phar; do \
        # The following PHP code throws an exception and returns non-zero if .phar can't be loaded
        # (e.g. due to a checksum mismatch)
        php -r "new Phar(\"${phar}\");"; \
    done
# Slack plugin for OSTicket
ENV OSTICKET_SLACK_VERSION=15c0cadfbc0c0548cde5750eda5f29d36381683b \
    OSTICKET_SLACK_SHA256SUM=635e024176742116f288146b6d7397f614be0ef812cbbffbc649789cc51bbb79
RUN set -ex; \
    \
    wget -q -O osTicket-slack-plugin.tar.gz https://github.com/clonemeagain/\
osticket-slack/archive/${OSTICKET_SLACK_VERSION}.tar.gz; \
    echo "${OSTICKET_SLACK_SHA256SUM}  osTicket-slack-plugin.tar.gz" | sha256sum -c; \
    mkdir /var/www/html/include/plugins/slack; \
    tar -xzf osTicket-slack-plugin.tar.gz -C /var/www/html/include/plugins/slack \
        --strip-components=1; \
    rm osTicket-slack-plugin.tar.gz; \
    chown -R www-data:www-data /var/www/html/include/plugins/slack
COPY root /
CMD ["start"]
STOPSIGNAL SIGTERM
EXPOSE 80
HEALTHCHECK CMD curl -fIsS http://localhost/ || exit 1
