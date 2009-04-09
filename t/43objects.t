#!/usr/bin/perl -w

use strict;

use Test::More tests => 7;
use IO::Async::Test;
use IO::Async::Loop;

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
use Tangence::Connection;

use t::Ball;
use t::Bag;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $bag = $registry->construct(
   "t::Bag",
   colours => [ qw( red ) ],
);

my $ball = $bag->get_ball( "red" );
my $ballid = $ball->id;

my $server = Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

$server->new_be( handle => $S1 );

my $conn = Tangence::Connection->new( handle => $S2 );
$loop->add( $conn );

wait_for { defined $conn->get_root };

my $bagproxy = $conn->get_root;

my $ballproxy;

$bagproxy->call_method(
   method => "pull_ball",
   args   => [ "red" ],
   on_result => sub { $ballproxy = shift },
);

wait_for { defined $ballproxy };

ok( $ballproxy->proxy_isa( "t::Ball" ), 'proxy for isa t::Ball' );

is_deeply( $ballproxy->can_method( "bounce" ),
           { args => [qw( str )], ret => "str" },
           'proxy can_method bounce' );

my $colour;

my $watched;
$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
   on_watched => sub { $watched = 1 },
);

wait_for { $watched };

$ball->set_prop_colour( "green" );

wait_for { defined $colour };

is( $colour, "green", '$colour is green from first object' );

# Now destroy the ball
my $ball_destroyed;
$ball->subscribe_event( destroy => sub { $ball_destroyed = 1 } );

my $ballproxy_destroyed;
$ballproxy->subscribe_event(
   event => "destroy",
   on_fire => sub { $ballproxy_destroyed = 1 } );

my @destroyed;
$registry->subscribe_event( object_destroyed => sub { push @destroyed, $_[2] } );

$ball->destroy;

wait_for { $ball_destroyed };
wait_for { $ballproxy_destroyed };
wait_for { @destroyed };

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

wait_for { defined $ballproxy };

is( $ballproxy->id, $ballid, 'New ball proxy reuses old object id' );

$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
   on_watched => sub { $watched = 1 },
);

$watched = 0;
wait_for { $watched };

$ball->set_prop_colour( "yellow" );

undef $colour;
wait_for { defined $colour };

is( $colour, "yellow", '$colour is yellow from second object' );
