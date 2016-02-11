#!perl

use 5.010;
use strict;
use warnings;

use Test::More 0.98;
use Test::WithDB;

my $twdb = Test::WithDB->new(config_profile=>'twdb-test-mysql');
my $dbh = $twdb->create_db;
ok($dbh);
undef $twdb;

DONE_TESTING:
done_testing;
