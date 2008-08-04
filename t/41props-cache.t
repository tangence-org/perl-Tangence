#!/usr/bin/perl -w

use strict;

use Test::More tests => 15;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
use Tangence::Connection;
use t::TestObj;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $obj = $registry->construct(
   "t::TestObj",
);

my $server = Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

$server->new_be( handle => $S1 );

my $conn = Tangence::Connection->new( handle => $S2 );
$loop->add( $conn );

my $proxy = $conn->get_by_id( "1" );

my $result;

my $scalar_changed = 0;
$proxy->watch_property(
   property => "scalar",
   on_change => sub { $scalar_changed = 1 },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

is( $proxy->get_property_cached( "scalar" ), 
   "123",
    "scalar property cache" );

my $hash_changed = 0;
$proxy->watch_property(
   property => "hash",
   on_change => sub { $hash_changed = 1 },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

is_deeply( $proxy->get_property_cached( "hash" ),
           { one => 1, two => 2, three => 3 },
           'hash property cache' );

my $array_changed = 0;
$proxy->watch_property(
   property => "array",
   on_change => sub { $array_changed = 1 },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

is_deeply( $proxy->get_property_cached( "array" ),
           [ 1, 2, 3 ],
           'array property cache' );

$obj->add_number( four => 4 );

$array_changed = 0;
wait_for { $array_changed };

is( $proxy->get_property_cached( "scalar" ), 
    "1234",
    "scalar property cache after update" );
is_deeply( $proxy->get_property_cached( "hash" ), 
           { one => 1, two => 2, three => 3, four => 4 },
           'hash property cache after update' );
is_deeply( $proxy->get_property_cached( "array" ),
           [ 1, 2, 3, 4 ],
           'array property cache after update' );

$scalar_changed = $hash_changed = $array_changed = 0;

$obj->add_number( five => 4 );

wait_for { $hash_changed };

ok( !$scalar_changed, 'scalar unchanged' );
ok( !$array_changed,  'array unchanged' );
is_deeply( $proxy->get_property_cached( "hash" ),
           { one => 1, two => 2, three => 3, four => 4, five => 4 },
           'hash property cache after wrong five' );

$scalar_changed = $hash_changed = $array_changed = 0;

$obj->add_number( five => 5 );

wait_for { $hash_changed };

is( $proxy->get_property_cached( "scalar" ),
    "12345",
    "scalar property cache after five" );
is_deeply( $proxy->get_property_cached( "hash" ),
           { one => 1, two => 2, three => 3, four => 4, five => 5 },
           'hash property cache after five' );
is_deeply( $proxy->get_property_cached( "array" ),
           [ 1, 2, 3, 4, 5 ],
           'array property cache after five' );

$array_changed = 0;

$obj->del_number( 3 );

wait_for { $array_changed };

is( $proxy->get_property_cached( "scalar" ),
    "1245",
    "scalar property cache after delete three" );
is_deeply( $proxy->get_property_cached( "hash" ),
           { one => 1, two => 2, four => 4, five => 5 },
           'hash property cache after delete three' );
is_deeply( $proxy->get_property_cached( "array" ),
           [ 1, 2, 4, 5 ],
           'array property cache after delete three' );
