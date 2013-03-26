package Test::mysqld;

use strict;
use warnings;

use 5.008;
use Class::Accessor::Lite;
use Cwd;
use DBI;
use File::Copy::Recursive qw(dircopy);
use File::Temp qw(tempdir);
use POSIX qw(SIGTERM WNOHANG);
use Time::HiRes qw(sleep);

our $VERSION = '0.17';

our $errstr;
our @SEARCH_PATHS = qw(/usr/local/mysql);

my %Defaults = (
    auto_start       => 2,
    base_dir         => undef,
    my_cnf           => {},
    mysql_install_db => undef,
    mysqld           => undef,
    pid              => undef,
    copy_data_from   => undef,
    _owner_pid       => undef,
);

Class::Accessor::Lite->mk_accessors(keys %Defaults);

sub new {
    my $klass = shift;
    my $self = bless {
        %Defaults,
        @_ == 1 ? %{$_[0]} : @_,
        _owner_pid => $$,
    }, $klass;
    $self->my_cnf({
        %{$self->my_cnf},
    });
    if (defined $self->base_dir) {
        $self->base_dir(cwd . '/' . $self->base_dir)
            if $self->base_dir !~ m|^/|;
    } else {
        $self->base_dir(
            tempdir(
                CLEANUP => $ENV{TEST_MYSQLD_PRESERVE} ? undef : 1,
            ),
        );
    }
    $self->my_cnf->{socket} ||= $self->base_dir . "/tmp/mysql.sock";
    $self->my_cnf->{datadir} ||= $self->base_dir . "/var";
    $self->my_cnf->{'pid-file'} ||= $self->base_dir . "/tmp/mysqld.pid";
    $self->my_cnf->{tmpdir} ||= $self->base_dir . "/tmp";
    if (! defined $self->mysql_install_db) {
        my $prog = _find_program(qw/mysql_install_db bin scripts/)
            or return;
        $self->mysql_install_db($prog);
    }
    if (! defined $self->mysqld) {
        my $prog = _find_program(qw/mysqld bin libexec sbin/)
            or return;
        $self->mysqld($prog);
    }
    if ($self->auto_start) {
        die 'mysqld is already running (' . $self->my_cnf->{'pid-file'} . ')'
            if -e $self->my_cnf->{'pid-file'};
        $self->setup
            if $self->auto_start >= 2;
        $self->start;
    }
    $self;
}

sub DESTROY {
    my $self = shift;
    $self->stop
        if defined $self->pid && $$ == $self->_owner_pid;
}

sub dsn {
    my ($self, %args) = @_;
    $args{port} ||= $self->my_cnf->{port}
        if $self->my_cnf->{port};
    if (defined $args{port}) {
        $args{host} ||= $self->my_cnf->{'bind-address'} || '127.0.0.1';
    } else {
        $args{mysql_socket} ||= $self->my_cnf->{socket};
    }
    $args{user} ||= 'root';
    $args{dbname} ||= 'test';
    return 'DBI:mysql:' . join(';', map { "$_=$args{$_}" } sort keys %args);
}

sub start {
    my $self = shift;
    return
        if defined $self->pid;
    open my $logfh, '>>', $self->base_dir . '/tmp/mysqld.log'
        or die 'failed to create log file:' . $self->base_dir
            . "/tmp/mysqld.log:$!";
    my $pid = fork;
    die "fork(2) failed:$!"
        unless defined $pid;
    if ($pid == 0) {
        open STDOUT, '>&', $logfh
            or die "dup(2) failed:$!";
        open STDERR, '>&', $logfh
            or die "dup(2) failed:$!";
        exec(
            $self->mysqld,
            '--defaults-file=' . $self->base_dir . '/etc/my.cnf',
            '--user=root',
        );
        die "failed to launch mysqld:$?";
    }
    close $logfh;
    while (! -e $self->my_cnf->{'pid-file'}) {
        if (waitpid($pid, WNOHANG) > 0) {
            die "*** failed to launch mysqld ***\n" . $self->read_log;
        }
        sleep 0.1;
    }
    $self->pid($pid);
    { # create 'test' database
        my $dbh = DBI->connect($self->dsn(dbname => 'mysql'))
            or die $DBI::errstr;
        $dbh->do('CREATE DATABASE IF NOT EXISTS test')
            or die $dbh->errstr;
    }
}

sub stop {
    my ($self, $sig) = @_;

    local $?; # waitpid may change this value :/
    return
        unless defined $self->pid;
    $sig ||= SIGTERM;
    kill $sig, $self->pid;
    while (waitpid($self->pid, 0) <= 0) {
    }
    $self->pid(undef);
    # might remain for example when sending SIGKILL
    unlink $self->my_cnf->{'pid-file'};
}

sub setup {
    my $self = shift;
    # (re)create directory structure
    mkdir $self->base_dir;
    for my $subdir (qw/etc var tmp/) {
        mkdir $self->base_dir . "/$subdir";
    }
    # copy data files
    if ($self->copy_data_from) {
        dircopy($self->copy_data_from, $self->my_cnf->{datadir})
            or die(
                "could not dircopy @{[$self->copy_data_from]} to "
                    . "@{[$self->my_cnf->{datadir}]}:$!"
                );
    }
    # my.cnf
    open my $fh, '>', $self->base_dir . '/etc/my.cnf'
        or die "failed to create file:" . $self->base_dir . "/etc/my.cnf:$!";
    print $fh "[mysqld]\n";
    print $fh map {
        my $v = $self->my_cnf->{$_};
        defined $v && length $v
            ? "$_=$v" . "\n"
                : "$_\n";
    } sort keys %{$self->my_cnf};
    close $fh;
    # mysql_install_db
    if (! -d $self->base_dir . '/var/mysql') {
        my $cmd = $self->mysql_install_db;
        # We should specify --defaults-file option first.
        $cmd .= " --defaults-file='" . $self->base_dir . "/etc/my.cnf'";
        my $mysql_base_dir = $self->mysql_install_db;
        if (-l $mysql_base_dir) {
            require File::Spec;
            require File::Basename;
            my $base = File::Basename::dirname($mysql_base_dir);
            $mysql_base_dir = File::Spec->rel2abs(readlink($mysql_base_dir), $base);
        }
        if ($mysql_base_dir =~ s|/[^/]+/mysql_install_db$||) {
            $cmd .= " --basedir='$mysql_base_dir'";
        }
        $cmd .= " 2>&1";
        open $fh, '-|', $cmd
            or die "failed to spawn mysql_install_db:$!";
        my $output;
        while (my $l = <$fh>) {
            $output .= $l;
        }
        close $fh
            or die "*** mysql_install_db failed ***\n$output\n";
    }
}

sub read_log {
    my $self = shift;
    open my $logfh, '<', $self->base_dir . '/tmp/mysqld.log'
        or die "failed to open file:tmp/mysql.log:$!";
    do { local $/; <$logfh> };
}

sub _find_program {
    my ($prog, @subdirs) = @_;
    undef $errstr;
    my $path = _get_path_of($prog);
    return $path
        if $path;
    for my $mysql (_get_path_of('mysql'),
                   map { "$_/bin/mysql" } @SEARCH_PATHS) {
        if (-x $mysql) {
            for my $subdir (@subdirs) {
                $path = $mysql;
                if ($path =~ s|/bin/mysql$|/$subdir/$prog|
                        and -x $path) {
                    return $path;
                }
            }
        }
    }
    $errstr = "could not find $prog, please set appropriate PATH";
    return;
}

sub _get_path_of {
    my $prog = shift;
    my $path = `which $prog 2> /dev/null`;
    chomp $path
        if $path;
    $path = ''
        unless -x $path;
    $path;
}

"lestrrat-san he";
__END__

=head1 NAME

Test::mysqld - mysqld runner for tests

=head1 SYNOPSIS

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

=head1 DESCRIPTION

C<Test::mysqld> automatically setups a mysqld instance in a temporary directory, and destroys it when the perl script exits.

=head1 FUNCTIONS

=head2 new

Create and run a mysqld instance.  The instance is terminated when the returned object is being DESTROYed.  If required programs (mysql_install_db and mysqld) were not found, the function returns undef and sets appropriate message to $Test::mysqld::errstr.

=head2 base_dir

Returns directory under which the mysqld instance is being created.  The property can be set as a parameter of the C<new> function, in which case the directory will not be removed at exit.

=head2 copy_data_from

If specified, uses a copy of the specified directory as the data directory of MySQL.  "Mysql" database (which is used to store admistrative information) is automatically created if necessary by invoking mysql_install_db.

=head2 my_cnf

A hash containing the list of name=value pairs to be written into my.cnf.  The property can be set as a parameter of the C<new> function.

=head2 mysql_install_db

=head2 mysqld

Path to C<mysql_install_db> script or C<mysqld> program bundled to the mysqld distribution.  If not set, the program is automatically search by looking up $PATH and other prefixed directories.

=head2 dsn

Builds and returns dsn by using given parameters (if any).  Default username is 'root', and dbname is 'test'.

=head2 pid

Returns process id of mysqld (or undef if not running).

=head2 start

Starts mysqld.

=head2 stop

Stops mysqld.

=head2 setup

Setups the mysqld instance.

=head2 read_log

Returns the contents of the mysqld log file.

=head1 COPYRIGHT

Copyright (C) 2009 Cybozu Labs, Inc.  Written by Kazuho Oku.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
