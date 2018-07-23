use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;

my $mysqld = Test::mysqld->new(
    auto_start     => undef,
    my_cnf         => {
        'skip-networking' => '',
    },
) or plan skip_all => $Test::mysqld::errstr;

if (!$mysqld->_is_maria && ($mysqld->_mysql_major_version || 0) >= 8) {
    $mysqld->setup;
    $mysqld->start;
    my $dbh = DBI->connect($mysqld->dsn)
        or die "failed to connect to database:$DBI::errstr";

    $dbh->do('CREATE TABLE hello (
      id INTEGER PRIMARY KEY,
      str VARCHAR(191)
    )') or die $DBI::errstr;

    $dbh->do(q{INSERT INTO hello VALUES (
      1, 'hello'
    ), (
      2, 'ciao'
    )}) or die $DBI::errstr;
    $mysqld->stop;

    my $copydir = tempdir(CLEANUP => 1);
    mkdir $copydir . '/test';
    for my $d (qw(/ibdata1 /mysql.ibd /test/hello.ibd)) {
        copy $mysqld->my_cnf->{datadir} . $d, $copydir . $d;
    }
    undef $mysqld;

    $mysqld = Test::mysqld->new(
        copy_data_from => $copydir,
        auto_start     => undef,
        my_cnf         => {
            'skip-networking' => '',
        },
    ) or plan skip_all => $Test::mysqld::errstr;
}
else {
    $mysqld->copy_data_from('t/05-copy-data-from');
}

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
