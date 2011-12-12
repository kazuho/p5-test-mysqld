# run the parallel-tmp-tables tests in parallel.. with:
# prove -j4 t/1*

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

my $dsn = $mysqld->dsn;

my $dbh = DBI->connect($dsn);

ok $dbh->do("CREATE TEMPORARY TABLE t (a int, b int, c int) ENGINE MYISAM") => 'created tmp table';
ok $dbh->do("CREATE TEMPORARY TABLE t2 (a int, b int, c int) ENGINE MYISAM") => 'created tmp table';
ok $dbh->do("select * from t,t2") => 'select';
