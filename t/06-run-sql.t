use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;

my $mysqld = Test::mysqld->new(
    my_cnf         => {
        'skip-networking' => '',
    },
    run_sql_commands => [ 't/06-run-sql/deploy.sql' ],
) or plan skip_all => $Test::mysqld::errstr;

plan tests => 2;

my $dbh = DBI->connect($mysqld->dsn)
    or die "failed to connect to database:$DBI::errstr";

is_deeply(
    $dbh->selectall_arrayref(
        "SELECT id FROM example WHERE id = 20",
    ),
    [ [ 20 ] ],
);

is_deeply(
    $dbh->selectall_arrayref(
        "SELECT id FROM example WHERE id = 30",
    ),
    [],
);
