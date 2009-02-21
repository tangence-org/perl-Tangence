#!/usr/bin/perl -w

use strict;

use Test::More tests => 24;
use Test::HexString;
use IO::Async::Test;
use IO::Async::Loop;

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
$Tangence::Serialisation::SORT_HASH_KEYS = 1;

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

my $server = Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

my $be = $server->new_be( handle => $S1 );

is_deeply( $bag->get_prop_colours,
           { red => 1, blue => 1, green => 1, yellow => 1 },
           '$bag colours before pull' );

# MSG_GETROOT
$S2->syswrite( "\x40" . "\0\0\0\x0b" .
               "\x2a" . "testscript" );

my $expect;

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xc0" .
          "\xe2" . "t::Bag\0" .
                   "\x64" . "events\0"     . "\x61" . "destroy\0" . "\x61" . "args\0" . "\x20" .
                            "isa\0"        . "\x42" . "\x26" . "t::Bag" .
                                                      "\x30" . "Tangence::Object" .
                            "methods\0"    . "\x63" . "add_ball\0"  . "\x62" . "args\0" . "\x21" . "o" .
                                                                               "ret\0"  . "\x20" .
                                                      "get_ball\0"  . "\x62" . "args\0" . "\x21" . "s" .
                                                                               "ret\0"  . "\x21" . "o" .
                                                      "pull_ball\0" . "\x62" . "args\0" . "\x21" . "s" .
                                                                               "ret\0"  . "\x21" . "o" .
                            "properties\0" . "\x61" . "colours\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                             "type\0" . "\x21" . "i" .
                   "\x80" .
          "\xe1" . "\0\0\0\1" . "t::Bag\0" . "\x80" .
          "\x84" . "\0\0\0\1";

my $serverstream;

$serverstream = "";
wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream initially contains root object' );

is( $be->identity, "testscript", '$be->identity' );

# MSG_GETREGISTRY
$S2->syswrite( "\x41" . "\0\0\0\0" );

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xeb" .
          "\xe2" . "Tangence::Registry\0" .
                   "\x64" . "events\0"     . "\x63" . "destroy\0"            . "\x61" . "args\0" . "\x20" .
                                                      "object_constructed\0" . "\x61" . "args\0" . "\x21" . "I" .
                                                      "object_destroyed\0"   . "\x61" . "args\0" . "\x21" . "I" .
                            "isa\0"        . "\x42" . "\x32" . "Tangence::Registry" .
                                                      "\x30" . "Tangence::Object" .
                            "methods\0"    . "\x61" . "get_by_id\0" . "\x62" . "args\0" . "\x21" . "i" .
                                                                               "ret\0"  . "\x21" . "o" .
                            "properties\0" . "\x61" . "objects\0" . "\x62" . "dim\0"  . "\x21" . "2" .
                                                                             "type\0" . "\x21" . "s" .
                   "\x80" .
          "\xe1" . "\0\0\0\0" . "Tangence::Registry\0" . "\x80" .
          "\x84" . "\0\0\0\0";

$serverstream = "";
wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream initially contains registry' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x10" . 
               "\x21" . "1" .
               "\x29" . "pull_ball" .
               "\x23" . "red" );

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\0\xc4" .
          "\xe2" . "t::Ball\0" .
                   "\x64" . "events\0"     . "\x62" . "bounced\0" . "\x61" . "args\0" . "\x21" . "s" .
                                                      "destroy\0" . "\x61" . "args\0" . "\x20" .
                            "isa\0"        . "\x42" . "\x27" . "t::Ball" .
                                                      "\x30" . "Tangence::Object" .
                            "methods\0"    . "\x61" . "bounce\0" . "\x62" . "args\0" . "\x21" . "s" .
                                                                            "ret\0" . "\x20" .
                            "properties\0" . "\x62" . "colour\0" . "\x62" . "dim\0" . "\x21" . "1" .
                                                                            "type\0" . "\x21" . "i" .
                                                      "size\0"   . "\x63" . "auto\0" . "\x21" . "1" .
                                                                            "dim\0" . "\x21" . "1" .
                                                                            "type\0" . "\x21" . "i" .
                   "\x41" . "\x24" . "size" .
          "\xe1" . "\0\0\0\2" . "t::Ball\0" . "\x41" . "\x23" . "100" .
          "\x84" . "\0\0\0\2";

$serverstream = "";
wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to CALL' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1 },
           '$bag colours after pull' );

my $ball = $registry->get_by_id( 2 );

my $howhigh;
$ball->subscribe_event( bounced => sub {
      my ( $obj, $event, @args ) = @_;
      $howhigh = $args[0];
} );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x13" .
               "\x21" . "2" .
               "\x26" . "bounce" .
               "\x29" . "20 metres" );

wait_for { defined $howhigh };

ok( defined $t::Ball::last_bounce_ctx, 'defined $last_bounce_ctx' );

isa_ok( $t::Ball::last_bounce_ctx, "Tangence::Server::Context", '$last_bounce_ctx isa Tangence::Server::Context' );

is( $t::Ball::last_bounce_ctx->connection, $be, '$last_bounce_ctx->connection' );

is( $howhigh, "20 metres", '$howhigh is 20 metres after CALL' );

$expect = "\x82" . "\0\0\0\x09" .
          "\x28" . "bouncing";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to CALL' );

# MSG_SUBSCRIBE
$S2->syswrite( "\2" . "\0\0\0\x0a" .
               "\x21" . "2" .
               "\x27" . "bounced" );

$expect = "\x83" . "\0\0\0\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received MSG_SUBSCRIBED response' );

$ball->method_bounce( {}, "10 metres" );

$expect = "\4" . "\0\0\0\x14" .
          "\x21" . "2" .
          "\x27" . "bounced" .
          "\x29" . "10 metres";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received MSG_EVENT' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# MSG_GETPROP
$S2->syswrite( "\5" . "\0\0\0\x09" .
               "\x21" . "2" .
               "\x26" . "colour" );

$expect = "\x82" . "\0\0\0\4" .
          "\x23" . "red";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received property value after MSG_GETPROP' );

# MSG_SETPROP
$S2->syswrite( "\6" . "\0\0\0\x0e" .
               "\x21" . "2" .
               "\x26" . "colour" .
               "\x24" . "blue" );

$expect = "\x80" . "\0\0\0\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received OK after MSG_SETPROP' );

is( $ball->get_prop_colour, "blue", '$ball->colour is now blue' );

# MSG_WATCH
$S2->syswrite( "\7" . "\0\0\0\x0a" .
               "\x21" . "2" .
               "\x26" . "colour" .
               "\x20" );

$expect = "\x84" . "\0\0\0\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received MSG_WATCHING response' );

$ball->set_prop_colour( "orange" );

$expect = "\x09" . "\0\0\0\x12" .
          "\x21" . "2" .
          "\x26" . "colour" .
          "\x21" . "1" .
          "\x26" . "orange";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received property MSG_UPDATE notice' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# Test the autoproperties

$ball->set_prop_size( 200 );

$expect = "\x09" . "\0\0\0\x0d" .
          "\x21" . "2" .
          "\x24" . "size" .
          "\x21" . "1" .
          "\x23" . "200";

$serverstream = "";
wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received property MSG_UPDATE notice on autoprop' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x10" . 
               "\x21" . "1" .
               "\x28" . "add_ball" .
               "\x84" . "\0\0\0\2" );

$expect = "\x82" . "\0\0\0\1" .
          "\x80";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to "add_ball"' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1, orange => 1 },
           '$bag colours after add' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x12" .
               "\x21" . "1" .
               "\x28" . "get_ball" .
               "\x26" . "orange" );

$expect = "\x82" . "\0\0\0\5" .
          "\x84" . "\0\0\0\2";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'orange ball has same identity as red one earlier' );

# Test object destruction

my $obj_destroyed = 0;

$ball->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

# MSG_DESTROY
$expect = "\x0a" . "\0\0\0\2" .
          "\x21" . "2";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'MSG_DESTROY from server' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

wait_for { $obj_destroyed };
is( $obj_destroyed, 1, 'object gets destroyed' );
