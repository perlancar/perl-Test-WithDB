package Test::WithDB;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use DBI;
use POSIX qw(strftime);
use Test::More 0.98 ();
use UUID::Random;

sub new {
    my ($class, %attrs) = @_;

    my $self = bless \%attrs, $class;

    if (!$self->{config_path}) {
        # we're being tiny here, otherwise we'll use File::HomeDir
        my $home = $ENV{HOME} // $ENV{HOMEPATH}
            or die "Can't determine home directory";
        $self->{config_path} = "$home/test-withdb.ini";
    }

    $self->{_created_dbs} = [];
    $self->_init;
    $self;
}

sub _read_config {
    require Config::IOD::Reader;

    my $self = shift;
    $self->{_config} =
        Config::IOD::Reader->new->read_file($self->{config_path});
}

sub _init {
    my $self = shift;

    $self->_read_config;
    my $cfg = $self->{_config}{GLOBAL};

    my ($driver) = $cfg->{admin_dsn} =~ /^dbi:([^:]+)/;
    if ($driver !~ /^(Pg|SQLite)$/) {
        die "Sorry, DBI driver '$driver' is not supported yet";
    }

    $self->{_admin_dbh} = DBI->connect(
        $cfg->{admin_dsn}, $cfg->{admin_user}, $cfg->{admin_pass},
        {RaiseError=>1});
    $self->{_driver} = $driver;
}

sub create_db {
    my $self = shift;

    my $dbname = UUID::Random::generate();
    $dbname =~ s/-//g; $dbname = substr($dbname, 0, 8);
    $dbname = "testdb_".strftime("%Y%m%d_%H%M%S", localtime).
        "_$dbname"; # <= 64 chars

    my $cfg = $self->{_config}{GLOBAL};

    # XXX allow specifying more options
    Test::More::note("Creating test database '$dbname' ...");
    $log->debug     ("Creating test database '$dbname' ...");
    if ($self->{_driver} eq 'Pg') {
        $self->{_admin_dbh}->do("CREATE DATABASE $dbname OWNER $cfg->{user_user}");
    } elsif ($self->{_driver} eq 'SQLite') {
        # we don't need to do anything
    }
    push @{ $self->{_created_dbs}  }, $dbname;

    my $dsn = $cfg->{user_dsn};
    $dsn =~ s/%s/$dbname/
        or die "user_dsn in configuration file does not contain '%s': $dsn";

    {
        my $sql = $cfg->{init_sql_admin};
        last unless $sql;
        my $dbh = DBI->connect($dsn, $cfg->{admin_user}, $cfg->{admin_pass},
                               {RaiseError=>1});
        for my $st (ref($sql) eq 'ARRAY' ? @$sql : ($sql)) {
            Test::More::note("Initializing database by admin: $st ...");
            $log->debug     ("Initializing database by admin: $st ...");
            $dbh->do($st);
        }
    }

    my $dbh = DBI->connect($dsn, $cfg->{user_user}, $cfg->{user_pass},
                           {RaiseError=>1});
    {
        my $sql = $cfg->{init_sql_test};
        last unless $sql;
        for my $st (ref($sql) eq 'ARRAY' ? @$sql : ($sql)) {
            Test::More::note("Initializing database by test user: $st ...");
            $log->debug     ("Initializing database by test user: $st ...");
            $dbh->do($st);
        }
    }
    push @{ $self->{_dbhs} }, $dbh;
    $dbh;
}

sub _drop_dbs {
    my $self = shift;

    my $dbs = $self->{_created_dbs};

    for (0..@$dbs-1) {
        my $dbname = $dbs->[$_];
        my $dbh = $self->{_dbhs}[$_];
        $dbh->disconnect;
        Test::More::note("Dropping test database '$dbname' ...");
        $log->debug     ("Dropping test database '$dbname' ...");
        $self->{_admin_dbh}->do("DROP DATABASE $dbname");
    }
}

sub done {
    my $self = shift;
    return if $self->{_done}++;

    if (Test::More->builder->is_passing) {
        $self->_drop_dbs;
    } else {
        my $dbs = $self->{_created_dbs};
        if (@$dbs) {
            Test::More::diag(
                "Tests failing, not removing databases created during testing ".
                                 "(".join(", ", @$dbs).")");
            $log->error(
                "Tests failing, not removing databases created during testing ".
                                 "(".join(", ", @$dbs).")");
        }
    }
}

sub DESTROY {
    my $self = shift;
    $self->done;
}

1;
# ABSTRACT: Framework for testing application using database

=head1 SYNOPSIS

In your C<~/test-withdb.ini>:

 admin_dsn ="dbi:Pg:dbname=template1;host=localhost"
 admin_user="postgres"
 admin_pass="adminpass"

 user_dsn ="dbi:Pg:dbname=%s;host=localhost"
 user_user="someuser"
 user_pass="somepass"

 # optional: SQL statements to initialize DB by test user after created
 init_sql_admin=CREATE EXTENSION citext

 # optional: SQL statements to initialize DB by test user after created
 init_sql_test=

In your test file:

 use Test::More;
 use Test::WithDB;

 my $twdb = Test::WithDB->new;

 my $dbh = $twdb->create_db; # create db with random name

 # do stuffs with dbh

 my $dbh2 = $twdb->create_db; # create another db

 # do more stuffs

 $twdb->done; # will drop all created databases, unless tests are not passing


=head1 DESCRIPTION

This class provides a simple framework for testing application that requires
database. It is meant to work with L<Test::More> (or to be more exact, any
L<Test::Builder>-based module).

First, you supply a configuration file containing admin and normal
user's connection information (the admin info is needed to create databases).

Then, you call one or more C<create_db()> to create one or more databases for
testing. The database will be created with random names.

At the end of testing, when you call C<< $twdb->done >>, the class will do this
check:

 if (Test::More->builder->is_passing) {
     # drop all created databases
 } else {
    diag "Tests failing, not removing databases created during testing: ...";
 }

So when testing fails, you can inspect the database.

Currently only supports Postgres and SQLite.


=head1 ATTRIBUTES

=head2 config_path => str (default: C<~/test-withdb.ini>).

Path to configuration file. File will be read using L<Config::IOD::Reader>.


=head1 METHODS

=head2 new(%attrs) => obj

=head2 $twdb->create_db

Create a test database with random name.

=head2 $twdb->done

Finish testing. Will drop all created databases unless tests are not passing.

Called automatically during DESTROY (but because object destruction order are
not guaranteed, it's best that you explicitly call C<done()> yourself).


=head1 SEE ALSO

L<Test::More>, L<Test::Builder>

=cut
