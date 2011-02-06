#!/usr/bin/perl -w

use strict;

use Test::More tests => 39;
use Test::Exception;
use Test::HexString;
use Test::Memory::Cycle;
use IO::Async::Test;
use IO::Async::Loop;

use Tangence::Constants;
use Tangence::Registry;

use t::Conversation;

use Net::Async::Tangence::Client;
$Tangence::Message::SORT_HASH_KEYS = 1;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

{
   my $clientstream = "";
   sub wait_for_message
   {
      my $msglen;
      wait_for_stream { length $clientstream >= 5 and
                        length $clientstream >= ( $msglen = 5 + unpack "xN", $clientstream ) } $S2 => $clientstream;

      return substr( $clientstream, 0, $msglen, "" );
   }
}

my $client = Net::Async::Tangence::Client->new(
   handle => $S1,
   on_error => sub { die "Test died early - $_[0]" },
   identity => "testscript",
);
$loop->add( $client );

is_hexstr( wait_for_message, $C2S{GETROOT}, 'client stream initially contains MSG_GETROOT' );

$S2->syswrite( $S2C{GETROOT} );

wait_for { defined $client->rootobj };

is_hexstr( wait_for_message, $C2S{GETREGISTRY}, 'client stream initially contains MSG_GETREGISTRY' );

$S2->syswrite( $S2C{GETREGISTRY} );

wait_for { defined $client->registry };

my $bagproxy = $client->rootobj;

# We'll need to wait for a result, where the result is 'undef' later... To do
# that neatly, we'll have an array that contains one element
my @result;

$bagproxy->call_method(
   method => "pull_ball",
   args   => [ "red" ],
   on_result => sub { push @result, shift },
);

is_hexstr( wait_for_message, $C2S{CALL_PULL}, 'client stream contains MSG_CALL' );

$S2->syswrite( $S2C{CALL_PULL} );

wait_for { @result };

isa_ok( $result[0], "Tangence::ObjectProxy", 'result contains an ObjectProxy' );

my $ballproxy = $result[0];

ok( $ballproxy->proxy_isa( "t::Ball" ), 'proxy for isa t::Ball' );

is_deeply( $ballproxy->can_method( "bounce" ),
           { args => [qw( str )], ret => "str" },
           'proxy can_method bounce' );

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
);

is_hexstr( wait_for_message, $C2S{CALL_BOUNCE}, 'client stream contains MSG_CALL' );

$S2->syswrite( $S2C{CALL_BOUNCE} );

wait_for { defined $result };

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

is_hexstr( wait_for_message, $C2S{SUBSCRIBE_BOUNCED}, 'client stream contains MSG_SUBSCRIBE' );

$S2->syswrite( $S2C{SUBSCRIBE_BOUNCED} );

wait_for { $subbed };

$S2->syswrite( $S2C{EVENT_BOUNCED} );

wait_for { defined $howhigh };

is( $howhigh, "10 metres", '$howhigh is 10 metres after MSG_EVENT' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK' );

my $bounced = 0;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub { $bounced = 1 }
);

$S2->syswrite( $S2C{EVENT_BOUNCED_5} );

wait_for { $bounced };

is( $howhigh, "5 metres", '$howhigh is orange after second MSG_EVENT' );
is( $bounced, 1, '$bounced is true after second MSG_EVENT' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK' );

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

is_hexstr( wait_for_message, $C2S{GETPROP_COLOUR}, 'client stream contains MSG_GETPROP' );

$S2->syswrite( $S2C{GETPROP_COLOUR_RED} );

wait_for { defined $colour };

is( $colour, "red", '$colour is red' );

my $didset = 0;
$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_done  => sub { $didset = 1 },
);

is_hexstr( wait_for_message, $C2S{SETPROP_COLOUR}, 'client stream contains MSG_SETPROP' );

$S2->syswrite( $MSG_OK );

wait_for { $didset };

my $watched;
$ballproxy->watch_property(
   property => "colour",
   on_set => sub { $colour = shift },
   on_watched => sub { $watched = 1 },
);

is_hexstr( wait_for_message, $C2S{WATCH_COLOUR}, 'client stream contains MSG_WATCH' );

$S2->syswrite( $S2C{WATCH_COLOUR} );

wait_for { $watched };

$S2->syswrite( $S2C{UPDATE_COLOUR_ORANGE} );

undef $colour;
wait_for { defined $colour };

is( $colour, "orange", '$colour is orange after MSG_UPDATE' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK' );

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

is_hexstr( wait_for_message, $C2S{GETPROP_COLOUR}, 'client stream contains MSG_GETPROP' );

$S2->syswrite( $S2C{GETPROP_COLOUR_GREEN} );

wait_for { $colourchanged };

is( $secondcolour, "green", '$secondcolour is green after second watch' );

$S2->syswrite( $S2C{UPDATE_COLOUR_YELLOW} );

$colourchanged = 0;
wait_for { $colourchanged };

is( $colour, "yellow", '$colour is yellow after second MSG_UPDATE' );
is( $colourchanged, 1, '$colourchanged is true after second MSG_UPDATE' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK' );

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

$S2->syswrite( $S2C{UPDATE_SIZE_200} );

undef $size;
wait_for { defined $size };

is( $size, 200, 'smashed prop watch succeeds' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK after smashed prop UPDATE' );

$bagproxy->call_method(
   method => "add_ball",
   args   => [ $ballproxy ],
   on_result => sub { push @result, shift },
);

is_hexstr( wait_for_message, $C2S{CALL_ADD}, 'client stream contains MSG_CALL with an ObjectProxy' );

$S2->syswrite( $S2C{CALL_ADD} );

undef @result;
wait_for { @result };

is( $result[0], undef, 'result is undef' );

# Test object destruction

my $proxy_destroyed = 0;

$ballproxy->subscribe_event(
   event => "destroy",
   on_fire => sub { $proxy_destroyed = 1 },
);

$S2->syswrite( $S2C{DESTROY} );

wait_for { $proxy_destroyed };
is( $proxy_destroyed, 1, 'proxy gets destroyed' );

is_hexstr( wait_for_message, $MSG_OK, 'client stream contains MSG_OK after MSG_DESTROY' );

memory_cycle_ok( $ballproxy, '$ballproxy has no memory cycles' );

# Deconfigure the clientection otherwise Devel::Cycle will throw
#   Unhandled type: GLOB at /usr/share/perl5/Devel/Cycle.pm line 107.
# on account of filehandles
$client->configure( transport => undef );
memory_cycle_ok( $client, '$client has no memory cycles' );
