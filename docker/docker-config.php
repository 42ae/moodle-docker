<?php

declare(strict_types=1);

$target = $argv[1] ?? '/var/www/html/config.php';
if (is_file($target)) {
    exit(0);
}

function env_value(string $name, string $default): string
{
    $value = getenv($name);
    return $value === false || $value === '' ? $default : $value;
}

function env_boolean(string $name): bool
{
    $value = filter_var(env_value($name, 'false'), FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
    if ($value === null) {
        fwrite(STDERR, "{$name} must be a boolean value.\n");
        exit(1);
    }
    return $value;
}

$dbtype = env_value('MOODLE_DB_TYPE', 'mysqli');
$dboptions = [
    'dbpersist' => false,
    'dbport' => env_value('MOODLE_DB_PORT', '3306'),
    'dbsocket' => false,
];

if ($dbtype === 'mysqli' || $dbtype === 'mariadb') {
    $dboptions['dbcollation'] = 'utf8mb4_unicode_ci';
}

$settings = [
    'dbtype' => $dbtype,
    'dblibrary' => 'native',
    'dbhost' => env_value('MOODLE_DB_HOST', 'database'),
    'dbname' => env_value('MOODLE_DB_NAME', 'moodle'),
    'dbuser' => env_value('MOODLE_DB_USER', 'root'),
    'dbpass' => env_value('MOODLE_DB_PASSWORD', ''),
    'prefix' => env_value('MOODLE_DB_PREFIX', 'mdl_'),
    'wwwroot' => env_value('MOODLE_WWW_ROOT', 'http://localhost'),
    'dataroot' => env_value('MOODLE_DATA_ROOT', '/var/www/moodledata'),
    'reverseproxy' => env_boolean('MOODLE_REVERSE_PROXY'),
    'sslproxy' => env_boolean('MOODLE_SSL_PROXY'),
];

$config = "<?php\n\n";
$config .= "unset(\$CFG);\n";
$config .= "global \$CFG;\n";
$config .= "\$CFG = new stdClass();\n\n";

foreach ($settings as $key => $value) {
    $config .= sprintf("\$CFG->%s = %s;\n", $key, var_export($value, true));
}

$config .= sprintf("\$CFG->dboptions = %s;\n", var_export($dboptions, true));
$config .= "\$CFG->directorypermissions = 02770;\n";
$config .= "\$CFG->routerconfigured = false;\n\n";
$config .= "require_once(__DIR__ . '/lib/setup.php');\n";

$directory = dirname($target);
$temporary = tempnam($directory, '.config.php.');
if ($temporary === false) {
    fwrite(STDERR, "Unable to create a temporary configuration file in {$directory}.\n");
    exit(1);
}

if (file_put_contents($temporary, $config, LOCK_EX) === false) {
    @unlink($temporary);
    fwrite(STDERR, "Unable to write Moodle configuration to {$temporary}.\n");
    exit(1);
}

chmod($temporary, 0640);
if (!rename($temporary, $target)) {
    @unlink($temporary);
    fwrite(STDERR, "Unable to move Moodle configuration into {$target}.\n");
    exit(1);
}
