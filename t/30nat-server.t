#!/usr/bin/perl -w

use strict;

use Test::More tests => 37;
use Test::HexString;
use Test::Identity;
use Test::Memory::Cycle;
use Test::Refcount;

use IO::Async::Test;
use IO::Async::Loop;
use IO::Async::Stream;

use Tangence::Constants;
use Tangence::Registry;

use t::Conversation;

use Net::Async::Tangence::Server;
$Tangence::Message::SORT_HASH_KEYS = 1;

use t::Ball;
use t::Bag;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $bag = $registry->construct(
   "t::Bag",
   colours => [ qw( red blue green yellow ) ],
   size => 100,
);

is_oneref( $bag, '$bag has refcount 1 initially' );

my $server = Net::Async::Tangence::Server->new(
   registry => $registry,
);

is_oneref( $server, '$server has refcount 1 initially' );

$loop->add( $server );

is_refcount( $server, 2, '$server has refcount 2 after $loop->add' );

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

{
   my $serverstream = "";
   sub wait_for_message
   {
      my $msglen;
      wait_for_stream { length $serverstream >= 5 and
                        length $serverstream >= ( $msglen = 5 + unpack "xN", $serverstream ) } $S2 => $serverstream;

      return substr( $serverstream, 0, $msglen, "" );
   }
}

my $conn = $server->on_stream( IO::Async::Stream->new( handle => $S1 ) );

is_refcount( $server, 2, '$server has refcount 2 after new BE' );
# Three refs: one in Server, one in IO::Async::Loop, one here
is_refcount( $conn, 3, '$conn has refcount 3 initially' );

is_deeply( $bag->get_prop_colours,
           { red => 1, blue => 1, green => 1, yellow => 1 },
           '$bag colours before pull' );

$S2->syswrite( $C2S{GETROOT} );

is_hexstr( wait_for_message, $S2C{GETROOT}, 'serverstream initially contains root object' );

is_oneref( $bag, '$bag has refcount 1 after MSG_GETROOT' );

is( $conn->identity, "testscript", '$conn->identity' );

$S2->syswrite( $C2S{GETREGISTRY} );

is_hexstr( wait_for_message, $S2C{GETREGISTRY}, 'serverstream initially contains registry' );

$S2->syswrite( $C2S{CALL_PULL} );

is_hexstr( wait_for_message, $S2C{CALL_PULL}, 'serverstream after response to CALL' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1 },
           '$bag colours after pull' );

my $ball = $registry->get_by_id( 2 );

my $cb_self;
my $howhigh;

$ball->subscribe_event( bounced => sub { ( $cb_self, $howhigh ) = @_; } );

$S2->syswrite( $C2S{CALL_BOUNCE} );

wait_for { defined $howhigh };

ok( defined $t::Ball::last_bounce_ctx, 'defined $last_bounce_ctx' );

isa_ok( $t::Ball::last_bounce_ctx, "Tangence::Server::Context", '$last_bounce_ctx isa Tangence::Server::Context' );

is( $t::Ball::last_bounce_ctx->stream, $conn, '$last_bounce_ctx->stream' );

identical( $cb_self, $ball, '$cb_self is $ball' );
is( $howhigh, "20 metres", '$howhigh is 20 metres after CALL' );

undef $cb_self;

is_hexstr( wait_for_message, $S2C{CALL_BOUNCE}, 'serverstream after response to CALL' );

$S2->syswrite( $C2S{SUBSCRIBE_BOUNCED} );

is_hexstr( wait_for_message, $S2C{SUBSCRIBE_BOUNCED}, 'received MSG_SUBSCRIBED response' );

$ball->method_bounce( {}, "10 metres" );

is_hexstr( wait_for_message, $S2C{EVENT_BOUNCED}, 'received MSG_EVENT' );

$S2->syswrite( $MSG_OK );

$S2->syswrite( $C2S{GETPROP_COLOUR} );

is_hexstr( wait_for_message, $S2C{GETPROP_COLOUR_RED}, 'received property value after MSG_GETPROP' );

$S2->syswrite( $C2S{SETPROP_COLOUR} );

is_hexstr( wait_for_message, $MSG_OK, 'received OK after MSG_SETPROP' );

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

$S2->syswrite( $C2S{WATCH_COLOUR} );

is_hexstr( wait_for_message, $S2C{WATCH_COLOUR}, 'received MSG_WATCHING response' );

$ball->set_prop_colour( "orange" );

is_hexstr( wait_for_message, $S2C{UPDATE_COLOUR_ORANGE}, 'received property MSG_UPDATE notice' );

$S2->syswrite( $MSG_OK );

# Test the smashed properties

$ball->set_prop_size( 200 );

is_hexstr( wait_for_message, $S2C{UPDATE_SIZE_200}, 'received property MSG_UPDATE notice on smashed prop' );

$S2->syswrite( $MSG_OK );

$S2->syswrite( $C2S{CALL_ADD} );

is_hexstr( wait_for_message, $S2C{CALL_ADD}, 'serverstream after response to "add_ball"' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1, orange => 1 },
           '$bag colours after add' );

$S2->syswrite( $C2S{CALL_GET} );

is_hexstr( wait_for_message, $S2C{CALL_GET}, 'orange ball has same identity as red one earlier' );

# Test object destruction

my $obj_destroyed = 0;

$ball->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

is_hexstr( wait_for_message, $S2C{DESTROY}, 'MSG_DESTROY from server' );

$S2->syswrite( $MSG_OK );

wait_for { $obj_destroyed };
is( $obj_destroyed, 1, 'object gets destroyed' );

is_oneref( $bag, '$bag has refcount 1 before shutdown' );

is_refcount( $server, 2, '$server has refcount 2 before $loop->remove' );

$loop->remove( $server );

is_oneref( $server, '$server has refcount 1 before shutdown' );

memory_cycle_ok( $bag, '$bag has no memory cycles' );
memory_cycle_ok( $registry, '$registry has no memory cycles' );
# Can't easily do $server yet because Devel::Cycle will throw
#   Unhandled type: GLOB at /usr/share/perl5/Devel/Cycle.pm line 107.
# on account of filehandles

$conn->close;
undef $server;

is_oneref( $conn, '$conn has refcount 1 after shutdown' );
