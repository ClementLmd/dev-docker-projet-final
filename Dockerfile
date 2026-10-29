# syntax=docker/dockerfile:1

FROM php:8.2-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libcap2-bin iputils-ping \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/apache2 \
    && mkdir -p /var/run/apache2 /var/lock/apache2 \
    && chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY docker/apache/app.conf /etc/apache2/sites-available/app.conf
RUN a2dissite 000-default \
    && a2ensite app

COPY --chown=www-data:www-data sources/app/ /var/www/html/

USER www-data

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["php", "-r", "exit(@fsockopen('127.0.0.1', 80) ? 0 : 1);"]
