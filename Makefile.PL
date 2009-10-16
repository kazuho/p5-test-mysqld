use strict;
use inc::Module::Install;

name 'Test-mysqld';
all_from 'lib/Test/mysqld.pm';

requires 'Class::Accessor::Lite';
test_requires 'DBI';
test_requires 'DBD::mysql';
test_requires 'Test::SharedFork' => 0.06;

WriteAll;
