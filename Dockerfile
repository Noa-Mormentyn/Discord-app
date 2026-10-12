FROM php:8.3-apache

# Extension PDO PostgreSQL (absente de l'image officielle) + outils pour Composer
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev unzip git \
    && docker-php-ext-install pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

# Le DocumentRoot pointe sur public/ : src/ et vendor/ restent hors du webroot
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Les dépendances d'abord : cette couche n'est reconstruite que si composer.* change
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist

# Puis le code (en dev, src/ et public/ sont remplacés par des volumes, voir docker-compose.yml)
COPY . .
