#!/usr/bin/perl -w

use strict;

use Test::More tests => 37;
use Test::Fatal qw( dies_ok );
use Test::HexString;
use Test::Memory::Cycle;

use Tangence::Constants;
use Tangence::Registry;

use t::Conversation;

$Tangence::Message::SORT_HASH_KEYS = 1;

my $client = TestClient->new();

is_hexstr( $client->recv_message, $C2S{GETROOT} . $C2S{GETREGISTRY}, 'client stream initially contains MSG_GETROOT and MSG_GETREGISTRY' );

$client->send_message( $S2C{GETROOT} );
$client->send_message( $S2C{GETREGISTRY} );

my $bagproxy = $client->rootobj;

# We'll need to wait for a result, where the result is 'undef' later... To do
# that neatly, we'll have an array that contains one element
my @result;

$bagproxy->call_method(
   method => "pull_ball",
   args   => [ "red" ],
   on_result => sub { push @result, shift },
);

is_hexstr( $client->recv_message, $C2S{CALL_PULL}, 'client stream contains MSG_CALL' );

$client->send_message( $S2C{CALL_PULL} );

isa_ok( $result[0], "Tangence::ObjectProxy", 'result contains an ObjectProxy' );

my $ballproxy = $result[0];

is_deeply( $ballproxy->introspect,
   {
      methods => {
         bounce  => { args => [qw( str )], ret => "str" },
      },
      events  => {
         bounced => { args => [qw( str )], },
         destroy => { args => [] },
      },
      properties => {
         colour  => { type => "str", dim => DIM_SCALAR },
         size    => { type => "int", dim => DIM_SCALAR, smash => 1 },
      },
      isa => [qw( t::Ball t::Colourable )],
   },
   '$ballproxy->introspect' );

ok( $ballproxy->proxy_isa( "t::Ball" ), 'proxy for isa t::Ball' );

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
);

is_hexstr( $client->recv_message, $C2S{CALL_BOUNCE}, 'client stream contains MSG_CALL' );

$client->send_message( $S2C{CALL_BOUNCE} );

is( $result, "bouncing", 'result of MSG_CALL' );

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

is_hexstr( $client->recv_message, $C2S{SUBSCRIBE_BOUNCED}, 'client stream contains MSG_SUBSCRIBE' );

$client->send_message( $S2C{SUBSCRIBE_BOUNCED} );

$client->send_message( $S2C{EVENT_BOUNCED} );

is( $howhigh, "10 metres", '$howhigh is 10 metres after MSG_EVENT' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

my $bounced = 0;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub { $bounced = 1 }
);

$client->send_message( $S2C{EVENT_BOUNCED_5} );

is( $howhigh, "5 metres", '$howhigh is orange after second MSG_EVENT' );
is( $bounced, 1, '$bounced is true after second MSG_EVENT' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

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

is_hexstr( $client->recv_message, $C2S{GETPROP_COLOUR}, 'client stream contains MSG_GETPROP' );

$client->send_message( $S2C{GETPROP_COLOUR_RED} );

is( $colour, "red", '$colour is red' );

my $didset = 0;
$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_done  => sub { $didset = 1 },
);

is_hexstr( $client->recv_message, $C2S{SETPROP_COLOUR}, 'client stream contains MSG_SETPROP' );

$client->send_message( $MSG_OK );

my $watched;
$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
   on_watched => sub { $watched = 1 },
);

is_hexstr( $client->recv_message, $C2S{WATCH_COLOUR}, 'client stream contains MSG_WATCH' );

$client->send_message( $S2C{WATCH_COLOUR} );

$client->send_message( $S2C{UPDATE_COLOUR_ORANGE} );

is( $colour, "orange", '$colour is orange after MSG_UPDATE' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

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

is_hexstr( $client->recv_message, $C2S{GETPROP_COLOUR}, 'client stream contains MSG_GETPROP' );

$client->send_message( $S2C{GETPROP_COLOUR_GREEN} );

is( $secondcolour, "green", '$secondcolour is green after second watch' );

$client->send_message( $S2C{UPDATE_COLOUR_YELLOW} );

is( $colour, "yellow", '$colour is yellow after second MSG_UPDATE' );
is( $colourchanged, 1, '$colourchanged is true after second MSG_UPDATE' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

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

$client->send_message( $S2C{UPDATE_SIZE_200} );

is( $size, 200, 'smashed prop watch succeeds' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after smashed prop UPDATE' );

undef @result;
$bagproxy->call_method(
   method => "add_ball",
   args   => [ $ballproxy ],
   on_result => sub { push @result, shift },
);

is_hexstr( $client->recv_message, $C2S{CALL_ADD}, 'client stream contains MSG_CALL with an ObjectProxy' );

$client->send_message( $S2C{CALL_ADD} );

is( $result[0], undef, 'result is undef' );

# Test object destruction

my $proxy_destroyed = 0;

$ballproxy->subscribe_event(
   event => "destroy",
   on_fire => sub { $proxy_destroyed = 1 },
);

$client->send_message( $S2C{DESTROY} );

is( $proxy_destroyed, 1, 'proxy gets destroyed' );

is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after MSG_DESTROY' );

memory_cycle_ok( $ballproxy, '$ballproxy has no memory cycles' );

package TestClient;

use strict;
use base qw( Tangence::Client );

sub new
{
   my $self = bless { written => "" }, shift;
   $self->identity( "testscript" );
   $self->on_error( sub { die "Test failed early - $_[0]" } );
   $self->tangence_connected;
   return $self;
}

sub tangence_write
{
   my $self = shift;
   $self->{written} .= $_[0];
}

sub send_message
{
   my $self = shift;
   my ( $message ) = @_;
   $self->tangence_readfrom( $message );
   length($message) == 0 or die "Client failed to read the whole message";
}

sub recv_message
{
   my $self = shift;
   my $message = $self->{written};
   $self->{written} = "";
   return $message;
}
