#!/usr/bin/perl -w

use strict;

use Test::More tests => 4;

use Tangence::Constants;
use Tangence::Registry;

use t::Ball;
use t::TestServerClient;

my $registry = Tangence::Registry->new();
my $ball = $registry->construct(
   "t::Ball",
   colour => "red",
   size   => 100,
);

my ( $server1, $client1 ) = make_serverclient( $registry );

my $ballproxy1 = $client1->rootobj;

my $colour1;

$ballproxy1->watch_property(
   property => "colour",
   on_set => sub { $colour1 = shift },
);

my ( $server2, $client2 ) = make_serverclient( $registry );

my $ballproxy2 = $client2->rootobj;

my $colour2;

$ballproxy2->watch_property(
   property => "colour",
   on_set => sub { $colour2 = shift },
);

$ball->set_prop_colour( "green" );

is( $colour1, "green", '$colour is green from connection 1' );
is( $colour2, "green", '$colour is green from connection 2' );

$client1->tangence_closed;
$server1->tangence_closed;

$ball->set_prop_colour( "blue" );

is( $colour1, "green", '$colour is still green from (closed) connection 1' );
is( $colour2, "blue", '$colour is blue from connection 2' );
