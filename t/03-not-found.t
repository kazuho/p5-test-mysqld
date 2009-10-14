use strict;
use warnings;

use DBI;
use Test::mysqld;

use Test::More tests => 3;

$ENV{PATH} = '/nonexistent';
@Test::mysqld::SEARCH_PATHS = ();

ok(! defined $Test::mysqld::errstr);
ok(! defined Test::mysqld->new(
    my_cnf => {
        'skip-networking' => '',
    },
));
ok($Test::mysqld::errstr);
