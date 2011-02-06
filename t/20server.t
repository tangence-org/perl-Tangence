#!/usr/bin/perl -w

use strict;

use Test::More tests => 32;
use Test::HexString;
use Test::Identity;
use Test::Memory::Cycle;
use Test::Refcount;

use Tangence::Constants;
use Tangence::Registry;

use t::Conversation;

use Tangence::Server;
$Tangence::Message::SORT_HASH_KEYS = 1;

use t::Ball;
use t::Bag;

my $registry = Tangence::Registry->new();
my $bag = $registry->construct(
   "t::Bag",
   colours => [ qw( red blue green yellow ) ],
   size => 100,
);

is_oneref( $bag, '$bag has refcount 1 initially' );

my $server = TestServer->new();
$server->registry( $registry );

is_oneref( $server, '$server has refcount 1 initially' );

is_deeply( $bag->get_prop_colours,
           { red => 1, blue => 1, green => 1, yellow => 1 },
           '$bag colours before pull' );

$server->send_message( $C2S{GETROOT} );

is_hexstr( $server->recv_message, $S2C{GETROOT}, 'serverstream initially contains root object' );

is_oneref( $bag, '$bag has refcount 1 after MSG_GETROOT' );

is( $server->identity, "testscript", '$server->identity' );

$server->send_message( $C2S{GETREGISTRY} );

is_hexstr( $server->recv_message, $S2C{GETREGISTRY}, 'serverstream initially contains registry' );

$server->send_message( $C2S{CALL_PULL} );

is_hexstr( $server->recv_message, $S2C{CALL_PULL}, 'serverstream after response to CALL' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1 },
           '$bag colours after pull' );

my $ball = $registry->get_by_id( 2 );

my $cb_self;
my $howhigh;

$ball->subscribe_event( bounced => sub { ( $cb_self, $howhigh ) = @_; } );

$server->send_message( $C2S{CALL_BOUNCE} );

ok( defined $t::Ball::last_bounce_ctx, 'defined $last_bounce_ctx' );

isa_ok( $t::Ball::last_bounce_ctx, "Tangence::Server::Context", '$last_bounce_ctx isa Tangence::Server::Context' );

is( $t::Ball::last_bounce_ctx->stream, $server, '$last_bounce_ctx->stream' );

identical( $cb_self, $ball, '$cb_self is $ball' );
is( $howhigh, "20 metres", '$howhigh is 20 metres after CALL' );

undef $cb_self;

is_hexstr( $server->recv_message, $S2C{CALL_BOUNCE}, 'serverstream after response to CALL' );

$server->send_message( $C2S{SUBSCRIBE_BOUNCED} );

is_hexstr( $server->recv_message, $S2C{SUBSCRIBE_BOUNCED}, 'received MSG_SUBSCRIBED response' );

$ball->method_bounce( {}, "10 metres" );

is_hexstr( $server->recv_message, $S2C{EVENT_BOUNCED}, 'received MSG_EVENT' );

$server->send_message( $MSG_OK );

$server->send_message( $C2S{GETPROP_COLOUR} );

is_hexstr( $server->recv_message, $S2C{GETPROP_COLOUR_RED}, 'received property value after MSG_GETPROP' );

$server->send_message( $C2S{SETPROP_COLOUR} );

is_hexstr( $server->recv_message, $MSG_OK, 'received OK after MSG_SETPROP' );

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

# MSG_WATCH
$server->send_message( $C2S{WATCH_COLOUR} );

is_hexstr( $server->recv_message, $S2C{WATCH_COLOUR}, 'received MSG_WATCHING response' );

$ball->set_prop_colour( "orange" );

is_hexstr( $server->recv_message, $S2C{UPDATE_COLOUR_ORANGE}, 'received property MSG_UPDATE notice' );

$server->send_message( $MSG_OK );

# Test the smashed properties

$ball->set_prop_size( 200 );

is_hexstr( $server->recv_message, $S2C{UPDATE_SIZE_200}, 'received property MSG_UPDATE notice on smashed prop' );

$server->send_message( $MSG_OK );

$server->send_message( $C2S{CALL_ADD} );

is_hexstr( $server->recv_message, $S2C{CALL_ADD}, 'serverstream after response to "add_ball"' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1, orange => 1 },
           '$bag colours after add' );

$server->send_message( $C2S{CALL_GET} );

is_hexstr( $server->recv_message, $S2C{CALL_GET}, 'orange ball has same identity as red one earlier' );

# Test object destruction

my $obj_destroyed = 0;

$ball->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

is_hexstr( $server->recv_message, $S2C{DESTROY}, 'MSG_DESTROY from server' );

$server->send_message( $MSG_OK );

is( $obj_destroyed, 1, 'object gets destroyed' );

is_oneref( $bag, '$bag has refcount 1 before shutdown' );

is_oneref( $server, '$server has refcount 1 before shutdown' );

memory_cycle_ok( $bag, '$bag has no memory cycles' );
memory_cycle_ok( $registry, '$registry has no memory cycles' );

package TestServer;

use strict;
use base qw( Tangence::Server );

sub new
{
   return bless { written => "" }, shift;
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
   length($message) == 0 or die "Server failed to read the whole message";
}

sub recv_message
{
   my $self = shift;
   my $message = $self->{written};
   $self->{written} = "";
   return $message;
}
