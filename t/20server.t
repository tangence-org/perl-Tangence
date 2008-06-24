#!/usr/bin/perl -w

use strict;

use Test::More tests => 9;
use Test::HexString;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;
use Tangence::Registry;
use Tangence::Server;
use t::Ball;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

my $registry = Tangence::Registry->new();
my $ball = $registry->construct(
   "t::Ball",
   colour => "red"
);

my $server = Tangence::Server->new(
   loop     => $loop,
   registry => $registry,
);

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

$server->new_be( handle => $S1 );

my $howhigh;
$ball->subscribe_event( bounced => sub {
      my ( $obj, $event, @args ) = @_;
      $howhigh = $args[0];
} );

# MSG_CALL
$S2->syswrite( "\1" . "\0\0\0\x18" .
               "\2" . "\3" . "\1" . "\x01" . "1" .
                             "\1" . "\x06" . "bounce" .
                             "\1" . "\x09" . "20 metres" );

wait_for { defined $howhigh };

is( $howhigh, "20 metres", '$howhigh is 20 metres after CALL' );

my $expect;
$expect = "\x82" . "\0\0\0\x0a" .
          "\1" . "\x08" . "bouncing";

my $serverstream;

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after response to CALL' );

# MSG_SUBSCRIBE
$S2->syswrite( "\2" . "\0\0\0\x0e" .
               "\2" . "\2" . "\1" . "\x01" . "1" .
                             "\1" . "\x07" . "bounced" );

# We're not sure quite what the response from the server will look like here,
# so we have to take it partially
$serverstream = "";

wait_for_stream { length $serverstream >= 5 } $S2 => $serverstream;
my ( $type, $len ) = unpack( "CN", $serverstream );
wait_for_stream { length $serverstream >= 5 + $len } $S2 => $serverstream;
( undef, undef, my $rawdata ) = unpack( "CNA*", $serverstream );

is( $type, MSG_SUBSCRIBED, 'response type is MSG_SUBSCRIBED' );

# We expect $rawdata to encode a single string, but we can't predict how long
# or what it will contain because it will be the ID of the subscribed event;
# which is actually a memory address
ok( $rawdata =~ m/^\x01/, 'response data encodes a string' );

$ball->bounce( "10 metres" );

$serverstream = "";

wait_for_stream { length $serverstream >= 5 } $S2 => $serverstream;
( $type, $len ) = unpack( "CN", $serverstream );
wait_for_stream { length $serverstream >= 5 + $len } $S2 => $serverstream;

is_hexstr( $serverstream, "\4" . "\0\0\0\x19" .
                          "\2" . "\3" . "\1" . "\x01" . "1" .
                                        "\1" . "\x07" . "bounced" .
                                        "\1" . "\x09" . "10 metres",
                          'message MSG_EVENT' );

# MSG_GETPROP
$S2->syswrite( "\5" . "\0\0\0\x0d" .
               "\2" . "\2" . "\1" . "\x01" . "1" .
                             "\1" . "\x06" . "colour" );

$expect = "\x82" . "\0\0\0\5" .
                   "\1" . "\x03" . "red";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received property value after MSG_GETPROP' );

# MSG_WATCH
$S2->syswrite( "\7" . "\0\0\0\x0f" .
               "\2" . "\3" . "\1" . "\x01" . "1" .
                             "\1" . "\x06" . "colour" .
                             "\1" . "\x00" );

# We're not sure quite what the response from the server will look like here,
# so we have to take it partially
$serverstream = "";

wait_for_stream { length $serverstream >= 5 } $S2 => $serverstream;
( $type, $len ) = unpack( "CN", $serverstream );
wait_for_stream { length $serverstream >= 5 + $len } $S2 => $serverstream;
( undef, undef, $rawdata ) = unpack( "CNA*", $serverstream );

is( $type, MSG_WATCHING, 'response type is MSG_WATCHING' );

# We expect $rawdata to encode a single string, but we can't predict how long
# or what it will contain because it will be the ID of the watched property;
# which is actually a memory address
ok( $rawdata =~ m/^\x01/, 'response data encodes a string' );

$ball->set_prop_colour( "green" );

$expect = "\x09" . "\0\0\0\x17" .
          "\2" . "\4" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "colour" .
                        "\1" . "\x01" . "1" .
                        "\1" . "\x05" . "green";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'received property MSG_UPDATE notice' );
