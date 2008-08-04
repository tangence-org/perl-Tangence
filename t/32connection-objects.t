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
use Tangence::Connection;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

my $conn = Tangence::Connection->new(
   handle => $S1,
   on_error => sub { die "Test died early - $_[0]" },
);
$loop->add( $conn );

my $bagproxy = $conn->get_root;

# We'll need to wait for a result, where the result is 'undef' later... To do
# that neatly, we'll have an array that contains one element
my @result;

$bagproxy->call_method(
   method => "pull_ball",
   args   => [ "red" ],
   on_result => sub { push @result, shift },
);

my $expect;

# MSG_CALL
$expect = "\1" . "\0\0\0\x13" . 
          "\1" . "\x01" . "1" .
          "\1" . "\x09" . "pull_ball" .
          "\1" . "\x03" . "red";

my $clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL' );

# MSG_RESULT

# This long string is massive and annoying. Sorry.

$S2->syswrite( "\x82" . "\0\0\1\x39" .
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
               "\4" . "\0\0\0\2" );

wait_for { @result };

ok( ref $result[0] && $result[0]->isa( "Tangence::ObjectProxy" ), 'result contains an ObjectProxy' );

my $ballproxy = $result[0];

ok( $ballproxy->proxy_isa( "t::Ball" ), 'proxy for isa t::Ball' );

is_deeply( $ballproxy->can_method( "bounce" ),
           { args => "s", ret => "" },
           'proxy can_method bounce' );

$bagproxy->call_method(
   method => "add_ball",
   args   => [ $ballproxy ],
   on_result => sub { push @result, shift },
);

# MSG_CALL
$expect = "\1" . "\0\0\0\x12" . 
          "\1" . "\x01" . "1" .
          "\1" . "\x08" . "add_ball" .
          "\4" . "\0\0\0\2";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL with an ObjectProxy' );

$S2->syswrite( "\x82" . "\0\0\0\1" .
               "\0" );

undef @result;
wait_for { @result };

is( $result[0], undef, 'result is undef' );
