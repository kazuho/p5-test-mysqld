use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;

my $mysqld = Test::mysqld->new(
    my_cnf => {
        'skip-networking' => '',
    },
) or plan skip_all => $Test::mysqld::errstr;

plan tests => 3;

my $base_dir = $mysqld->base_dir;
my $dsn = $mysqld->dsn;

is(
    $dsn,
    "DBI:mysql:dbname=test;mysql_socket=$base_dir/tmp/mysql.sock;user=root",
    'check dsn',
);

my $dbh = DBI->connect($dsn);
ok($dbh, 'connect to mysqld');

undef $mysqld;
sleep 1; # just in case
ok(! -e "$base_dir/tmp/mysql.sock", "mysqld is down");
