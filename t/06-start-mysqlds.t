use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;

Test::mysqld->new(
    my_cnf => {
        'skip-networking' => '',
    },
) or plan skip_all => $Test::mysqld::errstr;

plan tests => 3;

my @mysqld = Test::mysqld->start_mysqlds(
    2,
    my_cnf => {
        'skip-networking' => '',
    },
);
ok($mysqld[0]);
ok($mysqld[1]);
is(scalar @mysqld, 2);
Test::mysqld->stop_mysqlds(@mysqld);
