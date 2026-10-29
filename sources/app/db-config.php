<?php

function env_string(string $name): string
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        throw new RuntimeException('Variable d\'environnement manquante : ' . $name);
    }

    return $value;
}

$host = env_string('DB_HOST');
$port = env_string('DB_PORT');
$name = env_string('DB_NAME');

define('DB_DSN', sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8', $host, $port, $name));
define('DB_USER', env_string('DB_USER'));
define('DB_PASS', env_string('DB_PASS'));

$options = array(
    PDO::MYSQL_ATTR_INIT_COMMAND => 'SET NAMES utf8',
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_EMULATE_PREPARES => false,
);
