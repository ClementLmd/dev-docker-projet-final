# syntax=docker/dockerfile:1

FROM mysql:8.4

COPY sources/db/articles.sql /docker-entrypoint-initdb.d/01-articles.sql
