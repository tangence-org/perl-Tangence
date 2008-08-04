#!/usr/bin/perl -w

use strict;

use Test::More tests => 6;
use Test::HexString;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
$Tangence::Stream::SORT_HASH_KEYS = 1;

use t::Ball;
use t::Bag;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $bag = $registry->construct(
   "t::Bag",
   colours => [ qw( red blue green yellow ) ],
);

my $server = Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

$server->new_be( handle => $S1 );

is_deeply( $bag->get_prop_colours,
           { red => 1, blue => 1, green => 1, yellow => 1 },
           '$bag colours before pull' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x13" . 
               "\1" . "\x01" . "1" .
               "\1" . "\x09" . "pull_ball" .
               "\1" . "\x03" . "red" );

my $expect;

# This long string is massive and annoying. Sorry.

$expect = "\x82" . "\0\0\1\x39" .
          "\x82" . "t::Ball\0" .
                   "\3" . "\4" . "events\0" . "\3" . "\2" . "bounced\0" . "\3" . "\1" . "args\0" . "\1" . "\1" . "s" .
                                                            "destroy\0" . "\3" . "\1" . "args\0" . "\1" . "\0" .
                                 "isa\0" . "\2" . "\2" . "\1" . "\7" . "t::Ball" .
                                                         "\1" . "\x10" . "Tangence::Object" .
                                 "methods\0" . "\3" . "\6" . "bounce\0" . "\3" . "\2" . "args\0" . "\1" . "\1" . "s" .
                                                                                        "ret\0" . "\1" . "\0" .
                                                             "can_event\0" . "\3" . "\2" . "args\0" . "\1" . "\1" . "s" .
                                                                                           "ret\0" . "\1" . "\1" . "h" .
                                                             "can_method\0" . "\3" . "\2" . "args\0" . "\1" . "\1" . "s" .
                                                                                            "ret\0" . "\1" . "\1" . "h" .
                                                             "can_property\0" . "\3" . "\2" . "args\0" . "\1" . "\1" . "s" .
                                                                                              "ret\0" . "\1" . "\1" . "h" .
                                                             "describe\0" . "\3" . "\2" . "args\0" . "\1" . "\0" .
                                                                                          "ret\0" . "\1" . "\1" . "s" .
                                                             "introspect\0" . "\3" . "\2" . "args\0" . "\1" . "\0" .
                                                                                            "ret\0" . "\1" . "\1" . "h" .
                                 "properties\0" . "\3" . "\1" . "colour\0" . "\3" . "\2" . "dim\0" . "\1" . "\1" . "1" .
                                                                                           "type\0" . "\1" . "\1" . "i" .
          "\x81" . "\0\0\0\2" . "t::Ball\0" .
          "\4" . "\0\0\0\2";

my $serverstream;

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to CALL' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1 },
           '$bag colours after pull' );

# Some internal cheating
$registry->get_by_id(2)->set_prop_colour("orange");

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x12" . 
               "\1" . "\x01" . "1" .
               "\1" . "\x08" . "add_ball" .
               "\4" . "\0\0\0\2" );

$expect = "\x82" . "\0\0\0\1" .
          "\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to "add_ball"' );

is_deeply( $bag->get_prop_colours,
           { blue => 1, green => 1, yellow => 1, orange => 1 },
           '$bag colours after add' );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x15" .
               "\1" . "\x01" . "1" .
               "\1" . "\x08" . "get_ball" .
               "\1" . "\x06" . "orange" );

$expect = "\x82" . "\0\0\0\5" .
          "\4" . "\0\0\0\2";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'orange ball has same identity as red one earlier' );
