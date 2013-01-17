#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tangence::Constants;
use Tangence::Registry;

use t::Ball;
use t::TestServerClient;

my $registry = Tangence::Registry->new(
   tanfile => "t/Ball.tan",
);
my $ball = $registry->construct(
   "t::Ball",
   colour => "red",
   size   => 100,
);

my ( $conn1, $conn2 ) = map {
   my ( $server, $client ) = make_serverclient( $registry );

   my $ballproxy = $client->rootobj;

   my $conn = {
      server    => $server,
      client    => $client,
      ballproxy => $ballproxy,
   };

   $ballproxy->watch_property(
      property => "colour",
      on_set => sub { $conn->{colour} = shift },
   );

   $conn
} 1 .. 2;

$ball->set_prop_colour( "green" );

is( $conn1->{colour}, "green", '$colour is green from connection 1' );
is( $conn2->{colour}, "green", '$colour is green from connection 2' );

$conn1->{server}->tangence_closed;
$conn1->{client}->tangence_closed;

$ball->set_prop_colour( "blue" );

is( $conn1->{colour}, "green", '$colour is still green from (closed) connection 1' );
is( $conn2->{colour}, "blue", '$colour is blue from connection 2' );

done_testing;
