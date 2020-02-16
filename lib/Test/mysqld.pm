package Test::mysqld;

use strict;
use warnings;

use 5.008_001;
use Class::Accessor::Lite;
use Cwd;
use DBI;
use File::Copy::Recursive qw(dircopy);
use File::Temp qw(tempdir);
use POSIX qw(SIGTERM WNOHANG);
use Time::HiRes qw(sleep);

our $VERSION = '1.0013';

our $errstr;
our @SEARCH_PATHS = qw(/usr/local/mysql);

my %Defaults = (
    auto_start            => 2,
    base_dir              => undef,
    my_cnf                => {},
    mysqld                => undef,
    use_mysqld_initialize => undef,
    mysql_install_db      => undef,
    pid                   => undef,
    copy_data_from        => undef,
    _owner_pid            => undef,
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
    if (! defined $self->mysqld) {
        my $prog = _find_program(qw/mysqld bin libexec sbin/)
            or return;
        $self->mysqld($prog);
    }
    if (! defined $self->use_mysqld_initialize) {
        $self->use_mysqld_initialize($self->_use_mysqld_initialize);
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
    $self->spawn;
    $self->wait_for_setup;
}

sub spawn {
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
    $self->pid($pid);
}

sub wait_for_setup {
    my $self = shift;
    return
        unless defined $self->pid;
    my $pid = $self->pid;
    while (! -e $self->my_cnf->{'pid-file'}) {
        if (waitpid($pid, WNOHANG) > 0) {
            die "*** failed to launch mysqld ***\n" . $self->read_log;
        }
        sleep 0.1;
    }

    unless ($self->copy_data_from) { # create 'test' database
        my $dbh = DBI->connect($self->dsn(dbname => 'mysql'))
            or die $DBI::errstr;
        $dbh->do('CREATE DATABASE IF NOT EXISTS test')
            or die $dbh->errstr;
    }
}

sub stop {
    my ($self, $sig) = @_;

    return
        unless defined $self->pid;
    $sig ||= SIGTERM;
    $self->send_stop_signal($sig);
    $self->wait_for_stop;
}

sub send_stop_signal {
    my ($self, $sig) = @_;
    return
        unless defined $self->pid;
    $sig ||= SIGTERM;
    kill $sig, $self->pid;
}

sub wait_for_stop {
    my $self = shift;
    local $?; # waitpid may change this value :/
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

    # copy the data before setup db for quick bootstrap.
    if ($self->copy_data_from) {
        dircopy($self->copy_data_from, $self->my_cnf->{datadir})
            or die "could not dircopy @{[$self->copy_data_from]} to " .
                "@{[$self->my_cnf->{datadir}]}:$!";
        if (!$self->_is_maria && ($self->_mysql_major_version || 0) >= 8) {
            my $mysql_db_dir = $self->my_cnf->{datadir} . '/mysql';
            if (! -d $mysql_db_dir) {
                mkdir $mysql_db_dir or die "failed to mkdir $mysql_db_dir: $!";
            }
        }
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
        my $cmd = $self->use_mysqld_initialize ? $self->mysqld : do {
            if (! defined $self->mysql_install_db) {
                my $prog = _find_program(qw/mysql_install_db bin scripts/)
                    or die 'failed to find mysql_install_db';
                $self->mysql_install_db($prog);
            }
            $self->mysql_install_db;
        };

        # We should specify --defaults-file option first.
        $cmd .= " --defaults-file='" . $self->base_dir . "/etc/my.cnf'";

        if ($self->use_mysqld_initialize) {
            $cmd .= ' --initialize-insecure';
            if ($self->copy_data_from &&
                !(!$self->_is_maria && ($self->_mysql_major_version || 0) >= 8)
            ) {
                opendir my $dh, $self->copy_data_from
                    or die "failed to open copy_data_from directory @{[$self->copy_data_from]}: $!";
                while (my $entry = readdir $dh) {
                    next unless -d $self->copy_data_from . "/$entry";
                    next if $entry =~ /^\.\.?$/;
                    $cmd .= " --ignore-db-dir=$entry"
                }
            }
        } else {
            # `abs_path` resolves nested symlinks and returns canonical absolute path
            my $mysql_base_dir = Cwd::abs_path($self->mysql_install_db);
            if ($mysql_base_dir =~ s{/(?:bin|extra|scripts)/mysql_install_db$}{}) {
                $cmd .= " --basedir='$mysql_base_dir'";
            }
        }
        $cmd .= " 2>&1";
        # The MySQL scripts are in Perl, so clear out all current Perl
        # related environment variables before the call
        local @ENV{ grep { /^PERL/ } keys %ENV };
        open $fh, '-|', $cmd
            or die "failed to spawn mysql_install_db:$!";
        my $output;
        while (my $l = <$fh>) {
            $output .= $l;
        }
        close $fh
            or die "*** mysql_install_db failed ***\n% $cmd\n$output\n";
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

sub _verbose_help {
    my $self = shift;
    $self->{_verbose_help} ||= `@{[$self->mysqld]} --verbose --help 2>/dev/null`;
}

# Detecting if the mysqld supports `--initialize-insecure` option or not from the
# output of `mysqld --help --verbose`.
# `mysql_install_db` command is obsoleted MySQL 5.7.6 or later and
# `mysqld --initialize-insecure` should be used.
sub _use_mysqld_initialize {
    shift->_verbose_help =~ /--initialize-insecure/ms;
}

sub _is_maria {
    my $self = shift;
    unless (exists $self->{_is_maria}) {
        $self->{_is_maria} = $self->_verbose_help =~ /\A.*MariaDB/;
    }
    $self->{_is_maria};
}

sub _mysql_version {
    my $self = shift;
    unless (exists $self->{_mysql_version}) {
        ($self->{_mysql_version})
            = $self->_verbose_help =~ /\A.*Ver ([0-9]+\.[0-9]+\.[0-9]+)/;
    }
    $self->{_mysql_version};
}

sub _mysql_major_version {
    my $ver = shift->_mysql_version;
    return unless $ver;
    +(split /\./, $ver)[0];
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

sub start_mysqlds {
    my $class = shift;
    my $number = shift;
    my @args = @_;

    my @mysqlds = map { Test::mysqld->new(@args, auto_start => 0) } (1..$number);
    for my $mysqld (@mysqlds) {
        $mysqld->setup;
        $mysqld->spawn;
    }
    for my $mysqld (@mysqlds) {
        $mysqld->wait_for_setup;
    }
    return @mysqlds;
}

sub stop_mysqlds {
    my $class = shift;
    my @mysqlds = @_;

    for my $mysqld (@mysqlds) {
        $mysqld->send_stop_signal;
    }
    for my $mysqld (@mysqlds) {
        $mysqld->wait_for_stop;
    }
    return @mysqlds;
}

"lestrrat-san he";
__END__

=encoding utf-8

=for stopwords DESTROYed mysqld dsn dbname

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
  
  # start_mysqlds is faster than calling Test::mysqld->new twice
  my @mysqlds = Test::mysqld->start_mysqlds(
    2,
    my_cnf => {
      'skip-networking' => '', # no TCP socket
    }
  ) or plan skip_all => $Test::mysqld::errstr;
  Test::mysqlds->stop_mysqlds(@mysqlds);

=head1 DESCRIPTION

C<Test::mysqld> automatically setups a mysqld instance in a temporary directory, and destroys it when the perl script exits.

=head1 FUNCTIONS

=head2 new

Create and run a mysqld instance.  The instance is terminated when the returned object is being DESTROYed.  If required programs (mysql_install_db and mysqld) were not found, the function returns undef and sets appropriate message to $Test::mysqld::errstr.

=head2 base_dir

Returns directory under which the mysqld instance is being created.  The property can be set as a parameter of the C<new> function, in which case the directory will not be removed at exit.

=head2 copy_data_from

If specified, uses a copy of the specified directory as the data directory of MySQL.  "Mysql" database (which is used to store administrative information) is automatically created if necessary by invoking mysql_install_db.

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

=head2 start_mysqlds

Create and run some mysqld instances, and return a list of C<Test::mysqld>.

=head2 stop_mysqlds

Stop some mysqld instances.

=head1 COPYRIGHT

Copyright (C) 2009 Cybozu Labs, Inc.  Written by Kazuho Oku.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
