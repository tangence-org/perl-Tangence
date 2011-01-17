#!/usr/bin/perl -w

use strict;

use Test::More tests => 14;
use Test::Memory::Cycle;

use Tangence::Constants;
use Tangence::Registry;

use t::Ball;
use t::Bag;
use t::TestServerClient;

my $registry = Tangence::Registry->new(
   tanfile => "t/Bag.tan",
);
my $bag = $registry->construct(
   "t::Bag",
   colours => [ qw( red ) ],
);

my $ball = $bag->get_ball( "red" );
my $ballid = $ball->id;

my ( $server, $client ) = make_serverclient( $registry );

my $bagproxy = $client->rootobj;

my $ballproxy;

$bagproxy->call_method(
   method => "pull_ball",
   args   => [ "red" ],
   on_result => sub { $ballproxy = shift },
);

ok( $ballproxy->proxy_isa( "t::Ball" ), 'proxy for isa t::Ball' );

is_deeply( $ballproxy->can_method( "bounce" ),
           { args => [qw( str )], ret => "str" },
           'proxy can_method bounce' );

my $colour;

$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
);

$ball->set_prop_colour( "green" );

is( $colour, "green", '$colour is green from first object' );

# Now destroy the ball
my $ball_destroyed;
$ball->subscribe_event( destroy => sub { $ball_destroyed = 1 } );

my $ballproxy_destroyed;
$ballproxy->subscribe_event(
   event => "destroy",
   on_fire => sub { $ballproxy_destroyed = 1 } );

my @destroyed;
$registry->subscribe_event( object_destroyed => sub { push @destroyed, $_[1] } );

$ball->destroy;

ok( $ball_destroyed, 'Ball confirms destruction' );
ok( $ballproxy_destroyed, 'Ball proxy confirms destruction' );
is_deeply( \@destroyed, [ $ballid ], 'Registry confirms ball destroyed' );

undef $ball;
undef $ballproxy;

# Now recreate it - should have the same id
$ball = $registry->construct(
   "t::Ball",
   colour => "blue",
);

is( $ball->id, $ballid, 'New ball reuses old ball object id' );

$bag->add_ball( $ball );

$bagproxy->call_method(
   method => "get_ball",
   args   => [ "blue" ],
   on_result => sub { $ballproxy = shift },
);

is( $ballproxy->id, $ballid, 'New ball proxy reuses old object id' );

$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
);

$ball->set_prop_colour( "yellow" );

is( $colour, "yellow", '$colour is yellow from second object' );

memory_cycle_ok( $registry, '$registry has no memory cycles' );
memory_cycle_ok( $bag, '$bag has no memory cycles' );
memory_cycle_ok( $bagproxy, '$bagproxy has no memory cycles' );
memory_cycle_ok( $ball, '$ball has no memory cycles' );
memory_cycle_ok( $ballproxy, '$ballproxy has no memory cycles' );
