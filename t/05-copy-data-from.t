use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;
use Test::SharedFork;

my $mysqld = Test::mysqld->new(
    auto_start     => undef,
    copy_data_from => 't/05-copy-data-from',
    my_cnf         => {
        'skip-networking' => '',
    },
) or plan skip_all => $Test::mysqld::errstr;

plan tests => 1;

$mysqld->setup;
$mysqld->start;

my $dbh = DBI->connect($mysqld->dsn)
    or die "failed to connect to database:$DBI::errstr";

is_deeply(
    $dbh->selectall_arrayref(
        "select id,str from test.hello order by id",
    ),
    [
        [ 1, 'hello' ],
        [ 2, 'ciao' ],
    ],
);
