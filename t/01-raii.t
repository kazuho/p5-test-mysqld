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

plan tests => 2;

my $base_dir = $mysqld->base_dir;
my $dbh = DBI->connect(
    "DBI:mysql:test;mysql_socket=$base_dir/tmp/mysql.sock;user=root",
);
ok($dbh, 'connect to mysqld');

undef $mysqld;
sleep 1; # just in case
ok(! -e "$base_dir/tmp/mysql.sock", "mysqld is down");
