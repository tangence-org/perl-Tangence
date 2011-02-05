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

# MSG_GETROOT
$S2->syswrite( "\x40" . "\0\0\0\x0b" .
               "\x2a" . "testscript" );

my $expect;

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xcf" .
          "\xe2" . "t::Bag\0" .
                   "\x64" . "events\0"     . "\x61" . "destroy\0" . "\x61" . "args\0" . "\x40" .
                            "isa\0"        . "\x42" . "\x26" . "t::Bag" .
                                                      "\x30" . "Tangence::Object" .
                            "methods\0"    . "\x63" . "add_ball\0"  . "\x62" . "args\0" . "\x41" . "\x23" . "obj" .
                                                                               "ret\0"  . "\x20" .
                                                      "get_ball\0"  . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                               "ret\0"  . "\x23" . "obj" .
                                                      "pull_ball\0" . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                               "ret\0"  . "\x23" . "obj" .
                            "properties\0" . "\x61" . "colours\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                             "type\0" . "\x23" . "int" .
                   "\x40" .
          "\xe1" . "\0\0\0\1" . "t::Bag\0" . "\x40" .
          "\x84" . "\0\0\0\1";

is_hexstr( wait_for_message, $expect, 'serverstream initially contains root object' );

is_oneref( $bag, '$bag has refcount 1 after MSG_GETROOT' );

is( $conn->identity, "testscript", '$conn->identity' );

# MSG_GETREGISTRY
$S2->syswrite( "\x41" . "\0\0\0\0" );

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xf8" .
          "\xe2" . "Tangence::Registry\0" .
                   "\x64" . "events\0"     . "\x63" . "destroy\0"            . "\x61" . "args\0" . "\x40" .
                                                      "object_constructed\0" . "\x61" . "args\0" . "\x41" . "\x23" . "int" .
                                                      "object_destroyed\0"   . "\x61" . "args\0" . "\x41" . "\x23" . "int" .
                            "isa\0"        . "\x42" . "\x32" . "Tangence::Registry" .
                                                      "\x30" . "Tangence::Object" .
                            "methods\0"    . "\x61" . "get_by_id\0" . "\x62" . "args\0" . "\x41" . "\x23" . "int" .
                                                                               "ret\0"  . "\x23" . "obj" .
                            "properties\0" . "\x61" . "objects\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                             "type\0" . "\x23" . "str" .
                   "\x40" .
          "\xe1" . "\0\0\0\0" . "Tangence::Registry\0" . "\x40" .
          "\x84" . "\0\0\0\0";

is_hexstr( wait_for_message, $expect, 'serverstream initially contains registry' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x10" . 
               "\x02" . "\x01" .
               "\x29" . "pull_ball" .
               "\x23" . "red" );

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xe0" .
          "\xe2" . "t::Ball\0" .
                   "\x64" . "events\0"     . "\x62" . "bounced\0" . "\x61" . "args\0" . "\x41" . "\x23" . "str" .
                                                      "destroy\0" . "\x61" . "args\0" . "\x40" .
                            "isa\0"        . "\x43" . "\x27" . "t::Ball" .
                                                      "\x30" . "Tangence::Object" .
                                                      "\x2d" . "t::Colourable" .
                            "methods\0"    . "\x61" . "bounce\0" . "\x62" . "args\0" . "\x41" . "\x23" . "str" .
                                                                            "ret\0" . "\x23" . "str" .
                            "properties\0" . "\x62" . "colour\0" . "\x62" . "dim\0" . "\x21" . "1" .
                                                                            "type\0" . "\x23" . "str" .
                                                      "size\0"   . "\x63" . "dim\0" . "\x21" . "1" .
                                                                            "smash\0" . "\x21" . "1" .
                                                                            "type\0" . "\x23" . "int" .
                   "\x41" . "\x24" . "size" .
          "\xe1" . "\0\0\0\2" . "t::Ball\0" . "\x41" . "\x23" . "100" .
          "\x84" . "\0\0\0\2";

is_hexstr( wait_for_message, $expect, 'serverstream after response to CALL' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1 },
           '$bag colours after pull' );

my $ball = $registry->get_by_id( 2 );

my $cb_self;
my $howhigh;

$ball->subscribe_event( bounced => sub { ( $cb_self, $howhigh ) = @_; } );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x13" .
               "\x02" . "\x02" .
               "\x26" . "bounce" .
               "\x29" . "20 metres" );

wait_for { defined $howhigh };

ok( defined $t::Ball::last_bounce_ctx, 'defined $last_bounce_ctx' );

isa_ok( $t::Ball::last_bounce_ctx, "Tangence::Server::Context", '$last_bounce_ctx isa Tangence::Server::Context' );

is( $t::Ball::last_bounce_ctx->stream, $conn, '$last_bounce_ctx->stream' );

identical( $cb_self, $ball, '$cb_self is $ball' );
is( $howhigh, "20 metres", '$howhigh is 20 metres after CALL' );

undef $cb_self;

$expect = "\x82" . "\0\0\0\x09" .
          "\x28" . "bouncing";

is_hexstr( wait_for_message, $expect, 'serverstream after response to CALL' );

# MSG_SUBSCRIBE
$S2->syswrite( "\2" . "\0\0\0\x0a" .
               "\x02" . "\x02" .
               "\x27" . "bounced" );

$expect = "\x83" . "\0\0\0\0";

is_hexstr( wait_for_message, $expect, 'received MSG_SUBSCRIBED response' );

$ball->method_bounce( {}, "10 metres" );

$expect = "\4" . "\0\0\0\x14" .
          "\x02" . "\x02" .
          "\x27" . "bounced" .
          "\x29" . "10 metres";

is_hexstr( wait_for_message, $expect, 'received MSG_EVENT' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# MSG_GETPROP
$S2->syswrite( "\5" . "\0\0\0\x09" .
               "\x02" . "\x02" .
               "\x26" . "colour" );

$expect = "\x82" . "\0\0\0\4" .
          "\x23" . "red";

is_hexstr( wait_for_message, $expect, 'received property value after MSG_GETPROP' );

# MSG_SETPROP
$S2->syswrite( "\6" . "\0\0\0\x0e" .
               "\x02" . "\x02" .
               "\x26" . "colour" .
               "\x24" . "blue" );

$expect = "\x80" . "\0\0\0\0";

is_hexstr( wait_for_message, $expect, 'received OK after MSG_SETPROP' );

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

# MSG_WATCH
$S2->syswrite( "\7" . "\0\0\0\x0a" .
               "\x02" . "\x02" .
               "\x26" . "colour" .
               "\x00" );

$expect = "\x84" . "\0\0\0\0";

is_hexstr( wait_for_message, $expect, 'received MSG_WATCHING response' );

$ball->set_prop_colour( "orange" );

$expect = "\x09" . "\0\0\0\x12" .
          "\x02" . "\x02" .
          "\x26" . "colour" .
          "\x02" . "\x01" .
          "\x26" . "orange";

is_hexstr( wait_for_message, $expect, 'received property MSG_UPDATE notice' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# Test the smashed properties

$ball->set_prop_size( 200 );

$expect = "\x09" . "\0\0\0\x0b" .
          "\x02" . "\x02" .
          "\x24" . "size" .
          "\x02" . "\x01" .
          "\x02" . "\xc8"; # 0xC8 == 200

is_hexstr( wait_for_message, $expect, 'received property MSG_UPDATE notice on smashed prop' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x10" . 
               "\x02" . "\x01" .
               "\x28" . "add_ball" .
               "\x84" . "\0\0\0\2" );

$expect = "\x82" . "\0\0\0\0";

is_hexstr( wait_for_message, $expect, 'serverstream after response to "add_ball"' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1, orange => 1 },
           '$bag colours after add' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x12" .
               "\x02" . "\x01" .
               "\x28" . "get_ball" .
               "\x26" . "orange" );

$expect = "\x82" . "\0\0\0\5" .
          "\x84" . "\0\0\0\2";

is_hexstr( wait_for_message, $expect, 'orange ball has same identity as red one earlier' );

# Test object destruction

my $obj_destroyed = 0;

$ball->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

# MSG_DESTROY
$expect = "\x0a" . "\0\0\0\2" .
          "\x02" . "\x02";

is_hexstr( wait_for_message, $expect, 'MSG_DESTROY from server' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

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