#!/usr/bin/perl -w

use strict;

use Test::More tests => 9;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
use Tangence::Connection;
use t::Ball;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $ball = $registry->construct(
   "t::Ball",
   colour => "red",
   size   => 100,
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

wait_for { defined $conn->get_root };

my $ballproxy = $conn->get_root;

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
);

wait_for { defined $result };

is( $result, "bouncing", 'result of call_method()' );

my $error;
$ballproxy->call_method(
   method => "no_such_method",
   args   => [ 123 ],
   on_result => sub { die "Call returned a result - $_[0]" },
   on_error  => sub { $error = shift; },
);

wait_for { defined $error };

is( $error, "Object cannot respond to method no_such_method", '$error after call_method() to missing method' );

my $howhigh;
my $subbed;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub {
      my ( $obj, $event, @args ) = @_;
      $howhigh = $args[0];
   },
   on_subscribed => sub { $subbed = 1 },
);

wait_for { $subbed };

$ball->bounce( "10 metres" );

wait_for { defined $howhigh };

is( $howhigh, "10 metres", '$howhigh is 10 metres after subscribed event' );

my $colour;

$ballproxy->get_property(
   property => "colour",
   on_value => sub { $colour = shift },
);

wait_for { defined $colour };

is( $colour, "red", '$colour is red' );

my $didset = 0;
$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_done  => sub { $didset = 1 },
);

wait_for { $didset };

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

my $watched;
$ballproxy->watch_property(
   property => "colour",
   on_change => sub { 
      my ( $obj, $prop, $how, @value ) = @_;
      $colour = $value[0];
   },
   on_watched => sub { $watched = 1 },
);

wait_for { $watched };

$ball->set_prop_colour( "green" );

undef $colour;
wait_for { defined $colour };

is( $colour, "green", '$colour is green after MSG_UPDATE' );

my $colourchanged = 0;
my $secondcolour;
$ballproxy->watch_property(
   property => "colour",
   on_change => sub {
      ( undef, undef, undef, $secondcolour ) = @_;
      $colourchanged = 1
   },
   want_initial => 1,
);

wait_for { $colourchanged };

is( $secondcolour, "green", '$secondcolour is green after second watch' );

$ball->set_prop_colour( "orange" );

$colourchanged = 0;
wait_for { $colourchanged };

is( $colour, "orange", '$colour is orange after second MSG_UPDATE' );
is( $colourchanged, 1, '$colourchanged is true after second MSG_UPDATE' );
