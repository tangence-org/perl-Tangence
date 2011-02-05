#!/usr/bin/perl -w

use strict;

use Test::More tests => 3;
use IO::Async::Test;
use IO::Async::Loop;
use IO::Async::Stream;

use Tangence::Constants;
use Tangence::Registry;

use Net::Async::Tangence::Server;
use Net::Async::Tangence::Client;

use t::Ball;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $ball = $registry->construct(
   "t::Ball",
   colour => "red",
   size   => 100,
);

my $server = Net::Async::Tangence::Server->new(
   registry => $registry,
);

$loop->add( $server );

my ( $S1a, $S1b ) = $loop->socketpair() or die "Cannot create socket pair - $!";

$server->on_stream( IO::Async::Stream->new( handle => $S1a ) );

my $conn1 = Net::Async::Tangence::Client->new( handle => $S1b );
$loop->add( $conn1 );

wait_for { defined $conn1->rootobj };

my $ballproxy1 = $conn1->rootobj;

my $colour1;

my $watched;
$ballproxy1->watch_property(
   property => "colour",
   on_set => sub { $colour1 = shift },
   on_watched => sub { $watched = 1 },
);

wait_for { $watched };

my ( $S2a, $S2b ) = $loop->socketpair() or die "Cannot create socket pair - $!";

$server->on_stream( IO::Async::Stream->new( handle => $S2a ) );

my $conn2 = Net::Async::Tangence::Client->new( handle => $S2b );
$loop->add( $conn2 );

wait_for { defined $conn2->rootobj };

my $ballproxy2 = $conn2->rootobj;

my $colour2;

$watched = 0;
$ballproxy2->watch_property(
   property => "colour",
   on_set => sub { $colour2 = shift },
   on_watched => sub { $watched = 1 },
);

wait_for { $watched };

$ball->set_prop_colour( "green" );

wait_for { defined $colour1 and defined $colour2 };

is( $colour1, "green", '$colour is green from connection 1' );
is( $colour2, "green", '$colour is green from connection 2' );

$loop->remove( $conn1 );
$S1b->close;

my $waited = 0;
$loop->enqueue_timer( time => 0.1, code => sub { $waited = 1 } );
wait_for { $waited };

$ball->set_prop_colour( "blue" );

undef $colour2;
wait_for { defined $colour2 };

is( $colour2, "blue", '$colour is blue from connection 2' );
