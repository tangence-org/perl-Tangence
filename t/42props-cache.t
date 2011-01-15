#!/usr/bin/perl -w

use strict;

use Test::More tests => 21;
use Test::Memory::Cycle;
use IO::Async::Test;
use IO::Async::Loop;

use Tangence::Constants;
use Tangence::Registry;

use Net::Async::Tangence::Server;
use Net::Async::Tangence::Client;

use t::TestObj;

### TODO
# This test file relies a lot on weird logic in TestObj. Should probably instead just use 
# the object's property manip. methods directly
###

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $obj = $registry->construct(
   "t::TestObj",
);

my $server = Net::Async::Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

$server->new_conn( handle => $S1 );

my $conn = Net::Async::Tangence::Client->new( handle => $S2 );
$loop->add( $conn );

wait_for { defined $conn->get_root };

my $proxy = $conn->get_root;

my $result;

my $scalar;
my $scalar_changed = 0;
$proxy->watch_property(
   property => "scalar",
   on_set => sub {
      $scalar = shift;
      $scalar_changed = 1
   },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

wait_for { defined $scalar };

is( $scalar, "123", 'Initial value from watch_property' );

is( $proxy->prop( "scalar" ), 
   "123",
    "scalar property cache" );

my $hash_changed = 0;
$proxy->watch_property(
   property => "hash",
   on_updated => sub { $hash_changed = 1 },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

wait_for { defined eval { $proxy->prop( "hash" ) } };

is_deeply( $proxy->prop( "hash" ),
           { one => 1, two => 2, three => 3 },
           'hash property cache' );

my $array_changed = 0;
$proxy->watch_property(
   property => "array",
   on_updated => sub { $array_changed = 1 },
   on_watched => sub { $result = 1 },
   want_initial => 1,
);

undef $result;
wait_for { defined $result };

wait_for { defined eval { $proxy->prop( "array" ) } };

is_deeply( $proxy->prop( "array" ),
           [ 1, 2, 3 ],
           'array property cache' );

$obj->add_number( four => 4 );

$array_changed = 0;
wait_for { $scalar_changed and $hash_changed and $array_changed };

is( $proxy->prop( "scalar" ), 
    "1234",
    "scalar property cache after update" );
is_deeply( $proxy->prop( "hash" ), 
           { one => 1, two => 2, three => 3, four => 4 },
           'hash property cache after update' );
is_deeply( $proxy->prop( "array" ),
           [ 1, 2, 3, 4 ],
           'array property cache after update' );

$scalar_changed = $hash_changed = $array_changed = 0;

$obj->add_number( five => 4 );

wait_for { $hash_changed };

ok( !$scalar_changed, 'scalar unchanged' );
ok( !$array_changed,  'array unchanged' );
is_deeply( $proxy->prop( "hash" ),
           { one => 1, two => 2, three => 3, four => 4, five => 4 },
           'hash property cache after wrong five' );

$scalar_changed = $hash_changed = $array_changed = 0;

$obj->add_number( five => 5 );

wait_for { $scalar_changed and $hash_changed and $array_changed };

is( $proxy->prop( "scalar" ),
    "12345",
    "scalar property cache after five" );
is_deeply( $proxy->prop( "hash" ),
           { one => 1, two => 2, three => 3, four => 4, five => 5 },
           'hash property cache after five' );
is_deeply( $proxy->prop( "array" ),
           [ 1, 2, 3, 4, 5 ],
           'array property cache after five' );

$scalar_changed = $hash_changed = $array_changed = 0;

$obj->del_number( 3 );

wait_for { $scalar_changed and $hash_changed and $array_changed };

is( $proxy->prop( "scalar" ),
    "1245",
    "scalar property cache after delete three" );
is_deeply( $proxy->prop( "hash" ),
           { one => 1, two => 2, four => 4, five => 5 },
           'hash property cache after delete three' );
is_deeply( $proxy->prop( "array" ),
           [ 1, 2, 4, 5 ],
           'array property cache after delete three' );

# Just test this directly

$obj->set_prop_array( [ 0 .. 9 ] );

undef $array_changed;
wait_for { $array_changed };

$obj->move_prop_array( 3, 2 );

undef $array_changed;
wait_for { $array_changed };
is_deeply( $proxy->prop( "array" ),
           [ 0, 1, 2, 4, 5, 3, 6, 7, 8, 9 ],
           'array property cacahe after move(+2)' );

$obj->move_prop_array( 5, -2 );

undef $array_changed;
wait_for { $array_changed };
is_deeply( $proxy->prop( "array" ),
           [ 0 .. 9 ],
           'array property cacahe after move(-2)' );

memory_cycle_ok( $registry, '$registry has no memory cycles' );
memory_cycle_ok( $obj, '$obj has no memory cycles' );
memory_cycle_ok( $proxy, '$proxy has no memory cycles' );
