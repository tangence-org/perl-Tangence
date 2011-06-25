#!/usr/bin/perl -w

use strict;

use Test::More tests => 21;
use Test::Fatal qw( dies_ok );
use Test::Memory::Cycle;

use Tangence::Constants;
use Tangence::Registry;

use Tangence::Server;
use Tangence::Client;

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

my ( $server, $client ) = make_serverclient( $registry );

my $ballproxy = $client->rootobj;

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
);

is( $result, "bouncing", 'result of call_method()' );

dies_ok( sub { $ballproxy->call_method(
                 method => "no_such_method",
                 args   => [ 123 ],
                 on_result => sub {},
               ); },
         'Calling no_such_method fails in proxy' );

my $howhigh;
my $subbed;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub {
      ( $howhigh ) = @_;
   },
   on_subscribed => sub { $subbed = 1 },
);

$ball->method_bounce( {}, "10 metres" );

is( $howhigh, "10 metres", '$howhigh is 10 metres after subscribed event' );

dies_ok( sub { $ballproxy->subscribe_event(
                 event => "no_such_event",
                 on_fire => sub {},
               ); },
         'Subscribing to no_such_event fails in proxy' );

is( $ballproxy->prop( "size" ), 100, 'Smashed property initially set in proxy' );

my $colour;

$ballproxy->get_property(
   property => "colour",
   on_value => sub { $colour = shift },
);

is( $colour, "red", '$colour is red' );

my $didset = 0;
$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_done  => sub { $didset = 1 },
);

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

my $watched;
undef $colour;
$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
   on_watched => sub { $watched = 1 },
);

$ball->set_prop_colour( "green" );

is( $colour, "green", '$colour is green after MSG_UPDATE' );

my $colourchanged = 0;
my $secondcolour;
$ballproxy->watch_property(
   property => "colour",
   on_set => sub {
      $secondcolour = shift;
      $colourchanged = 1
   },
   want_initial => 1,
);

is( $secondcolour, "green", '$secondcolour is green after second watch' );

$ball->set_prop_colour( "orange" );

is( $colour, "orange", '$colour is orange after second MSG_UPDATE' );
is( $colourchanged, 1, '$colourchanged is true after second MSG_UPDATE' );

dies_ok( sub { $ballproxy->get_property(
                 property => "no_such_property",
                 on_value => sub {},
               ); },
         'Getting no_such_property fails in proxy' );

# Test the smashed properties

my $size;
$watched = 0;
$ballproxy->watch_property(
   property => "size",
   on_set => sub { $size = shift },
   on_watched => sub { $watched = 1 },
   want_initial => 1,
);

is( $watched, 1, 'watch_property on smashed prop is synchronous' );

is( $size, 100, 'watch_property on smashed prop gives initial value' );

undef $size;
$ball->set_prop_size( 200 );

is( $size, 200, 'smashed prop watch succeeds' );

# Test object destruction

my $proxy_destroyed = 0;

$ballproxy->subscribe_event(
   event => "destroy",
   on_fire => sub { $proxy_destroyed = 1 },
);

my $obj_destroyed = 0;

$ball->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

is( $proxy_destroyed, 1, 'proxy gets destroyed' );

is( $obj_destroyed, 1, 'object gets destroyed' );

memory_cycle_ok( $ball, '$ball has no memory cycles' );
memory_cycle_ok( $registry, '$registry has no memory cycles' );
memory_cycle_ok( $ballproxy, '$ballproxy has no memory cycles' );
memory_cycle_ok( $client, '$client has no memory cycles' );
