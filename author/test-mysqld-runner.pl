#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use autodie;

use Test::mysqld;

my $mysqld = Test::mysqld->new(
    auto_start => undef,
    my_cnf => {
        'skip-networking' => '', # no TCP socket
    },
) or die $Test::mysqld::errstr;

$SIG{TERM} = $SIG{INT} = sub {
    undef $mysqld;
    exit;
};

$mysqld->setup;

print STDERR "runner_pid:\n";
print STDERR "  $$\n";
print STDERR "mysql_version:\n";
print STDERR "  @{[$mysqld->_mysql_major_version]}\n";
print STDERR "is_maria:\n";
print STDERR "  @{[$mysqld->_is_maria ? 'true' : 'false']}\n";
print STDERR "base_dir:\n";
print STDERR "  @{[$mysqld->base_dir]}\n";
print STDERR "socket:\n";
print STDERR "  @{[$mysqld->my_cnf->{socket}]}\n";

$mysqld->start;

1 while 1;
