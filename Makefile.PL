use strict;
use inc::Module::Install;

name 'Test-mysqld';
all_from 'lib/Test/mysqld.pm';

requires 'Class::Accessor::Lite';
requires 'File::Copy::Recursive';
requires 'Path::Tiny';
test_requires 'DBI';
test_requires 'DBD::mysql';
test_requires 'Test::SharedFork' => 0.06;

repository 'https://github.com/kazuho/p5-test-mysqld';

WriteAll;
