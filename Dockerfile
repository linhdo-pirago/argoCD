# FE Build
FROM node:22-alpine AS builder

WORKDIR /app

RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    --mount=type=cache,target=/root/.npm \
    npm ci

COPY . .

RUN npm run build

# App
FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
      nginx execline shadow \
      libpng-dev jpeg-dev freetype-dev ffmpeg libzip-dev icu-dev

RUN set -x \
 && docker-php-ext-configure gd -with-freetype --with-jpeg > /dev/null \
 && docker-php-ext-install -j$(nproc) opcache pdo_mysql gd pcntl zip intl > /dev/null \
 && rm -rf /usr/src/php*

RUN groupmod -g 1000 www-data \
 && usermod -u 1000 www-data

# S6 Overlay
ARG S6_OVERLAY_VERSION=3.1.5.0

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
 && rm -f /tmp/s6-overlay-noarch.tar.xz

RUN curl -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-$(uname -m).tar.xz -o /tmp/s6-overlay-$(uname -m).tar.xz \
 && tar -C / -Jxpf /tmp/s6-overlay-$(uname -m).tar.xz \
 && rm -f /tmp/s6-overlay-$(uname -m).tar.xz

COPY .docker/s6-overlay/ /etc/s6-overlay/
COPY .docker/nginx/ /etc/nginx/http.d/

COPY .docker/php/php.ini /usr/local/etc/php/php.ini
COPY .docker/php-fpm/ /usr/local/etc/php-fpm.d/

ENV S6_STAGE_HOOK="/etc/s6-overlay/scripts/pre_hook"

# Composer
COPY --from=composer:2.5 /usr/bin/composer /usr/local/bin/composer

# Application
WORKDIR /app

COPY --chown=www-data:www-data composer* ./
RUN composer install --no-scripts --no-autoloader --no-cache -q

COPY --chown=www-data:www-data . .
RUN composer dump-autoload -o -q

COPY --from=builder --chown=www-data:www-data /app/public/build/ /app/public/build/

EXPOSE 80

ENTRYPOINT ["/init"]

