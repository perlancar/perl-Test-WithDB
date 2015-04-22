package Test::WithDB::SQLite;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use parent 'Test::WithDB';

sub _read_config {
    my $self = shift;

    my $path = $self->{config_path};
    my $cfg0;
    if (-f $path) {
        require Config::IOD::Reader;
        $cfg0 = Config::IOD::Reader->new->read_file($path);
    } else {
        $cfg0 = {};
    }
    my $profile = $self->{config_profile} // 'GLOBAL';
    my $cfg = $cfg0->{$profile} // {};

    $cfg->{admin_dsn}  //= 'dbi:SQLite:';
    $cfg->{admin_user} //= '';
    $cfg->{admin_pass} //= '';

    $cfg->{user_dsn}  //= 'dbi:SQLite:';
    $cfg->{user_user} //= '';
    $cfg->{user_pass} //= '';

    $cfg->{sqlite_db_dir} //= do {
        require File::Temp;
        File::Temp::tempdir(CLEANUP=>1);
    };

    $self->{_config} = $cfg;
}

1;
# ABSTRACT: A subclass of Test::WithDB that provide defaults for SQLite

=head1 SYNOPSIS

In your test file:

 use Test::More;
 use Test::WithDB::SQLite;

 my $twdb = Test::WithDB::SQLite->new;

 my $dbh = $twdb->create_db; # create db with random name

 # do stuffs with dbh

 my $dbh2 = $twdb->create_db; # create another db

 # do more stuffs

 $twdb->done; # will drop all created databases, unless tests are not passing


=head1 DESCRIPTION

This subclass of L<Test::WithDB> creates a convenience for use with SQLite.
Config file is not required, and by default SQLite databases will be created in
a temporary directory.


=head1 SEE ALSO

L<Test::WithDB>

=cut
