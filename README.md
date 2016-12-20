[![Build Status](https://travis-ci.org/kazuho/p5-test-mysqld.svg?branch=master)](https://travis-ci.org/kazuho/p5-test-mysqld)
# NAME

Test::mysqld - mysqld runner for tests

# SYNOPSIS

    use DBI;
    use Test::mysqld;
    use Test::More;
    
    my $mysqld = Test::mysqld->new(
      my_cnf => {
        'skip-networking' => '', # no TCP socket
      }
    ) or plan skip_all => $Test::mysqld::errstr;
    
    plan tests => XXX;
    
    my $dbh = DBI->connect(
      $mysqld->dsn(dbname => 'test'),
    );
    
    # start_mysqlds is faster than calling Test::mysqld->new twice
    my @mysqlds = Test::mysqld->start_mysqlds(
      2,
      my_cnf => {
        'skip-networking' => '', # no TCP socket
      }
    ) or plan skip_all => $Test::mysqld::errstr;
    Test::mysqlds->stop_mysqlds(@mysqlds);

# DESCRIPTION

`Test::mysqld` automatically setups a mysqld instance in a temporary directory, and destroys it when the perl script exits.

# FUNCTIONS

## new

Create and run a mysqld instance.  The instance is terminated when the returned object is being DESTROYed.  If required programs (mysql\_install\_db and mysqld) were not found, the function returns undef and sets appropriate message to $Test::mysqld::errstr.

## base\_dir

Returns directory under which the mysqld instance is being created.  The property can be set as a parameter of the `new` function, in which case the directory will not be removed at exit.

## copy\_data\_from

If specified, uses a copy of the specified directory as the data directory of MySQL.  "Mysql" database (which is used to store administrative information) is automatically created if necessary by invoking mysql\_install\_db.

## my\_cnf

A hash containing the list of name=value pairs to be written into my.cnf.  The property can be set as a parameter of the `new` function.

## mysql\_install\_db

## mysqld

Path to `mysql_install_db` script or `mysqld` program bundled to the mysqld distribution.  If not set, the program is automatically search by looking up $PATH and other prefixed directories.

## dsn

Builds and returns dsn by using given parameters (if any).  Default username is 'root', and dbname is 'test'.

## pid

Returns process id of mysqld (or undef if not running).

## start

Starts mysqld.

## stop

Stops mysqld.

## setup

Setups the mysqld instance.

## read\_log

Returns the contents of the mysqld log file.

## start\_mysqlds

Create and run some mysqld instances, and return a list of `Test::mysqld`.

## stop\_mysqlds

Stop some mysqld instances.

# COPYRIGHT

Copyright (C) 2009 Cybozu Labs, Inc.  Written by Kazuho Oku.

# LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See [http://www.perl.com/perl/misc/Artistic.html](http://www.perl.com/perl/misc/Artistic.html)
