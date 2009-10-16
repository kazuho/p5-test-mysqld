use strict;
use warnings;

use DBI;
use Test::More;
use Test::mysqld;
use Test::SharedFork;

my $mysqld = Test::mysqld->new(
    my_cnf => {
        'skip-networking' => '',
    },
) or plan skip_all => $Test::mysqld::errstr;

plan tests => 3;

ok(DBI->connect($mysqld->dsn), 'check if db is ready');

unless (my $pid = Test::SharedFork::fork) {
    die "fork failed:$!"
        unless defined $pid;
    # child process
    ok(DBI->connect($mysqld->dsn), 'connect from child process');
    exit 0;
}

1 while wait == -1;

ok(DBI->connect($mysqld->dsn), 'connect after child exit');
