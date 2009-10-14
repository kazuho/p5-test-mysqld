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

my @mysqld = map {
    my $mysqld = Test::mysqld->new(
        my_cnf => {
            'skip-networking' => '',
        },
    );
    ok($mysqld);
    $mysqld;
} 0..1;
is(scalar @mysqld, 2);
