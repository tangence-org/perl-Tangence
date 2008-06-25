#!/usr/bin/perl -w

use strict;

use Test::More tests => 2;
use Test::HexString;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Connection;
use t::Ball;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

my $conn = Tangence::Connection->new( handle => $S1 );
$loop->add( $conn );

my $response;

$conn->request(
   request => [ MSG_CALL, [ "1", "bounce", "20 metres" ] ],
   on_response => sub { $response = shift },
);

my $expect;

# MSG_CALL
$expect = "\1" . "\0\0\0\x18" .
          "\2" . "\3" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "bounce" .
                        "\1" . "\x09" . "20 metres";

my $clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL' );

# MSG_RESULT
$S2->syswrite( "\x82" . "\0\0\0\x0a" .
               "\1" . "\x08" . "bouncing" );

wait_for { defined $response };

is_deeply( $response, [ MSG_RESULT, "bouncing" ], 'response' );

## This is intentionally a much shorter test than 20server.t. All the real
## magic will be done in 31connection-objectproxy.t
