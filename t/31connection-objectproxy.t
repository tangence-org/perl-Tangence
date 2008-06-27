#!/usr/bin/perl -w

use strict;

use Test::More tests => 10;
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

my $conn = Tangence::Connection->new( handle => $S1 );
$loop->add( $conn );

my $ballproxy = $conn->get_by_id("1");

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
   on_error  => sub { die "Test died early - $_[0]" },
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

wait_for { defined $result };

is( $result, "bouncing", 'result of MSG_CALL' );

my $howhigh;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub {
      my ( $obj, $event, @args ) = @_;
      $howhigh = $args[0];
} );

# MSG_SUBSCRIBE
$expect = "\2" . "\0\0\0\x0e" .
          "\2" . "\2" . "\1" . "\x01" . "1" .
                        "\1" . "\x07" . "bounced";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_SUBSCRIBE' );

# MSG_SUBSCRIBED
$S2->syswrite( "\x83" . "\0\0\0\x0a" .
               "\1" . "\x08" . "12345678" );

# We can't easily wait_for anything here... so we'll get on with the next
# thing and check both afterwards

# MSG_EVENT
$S2->syswrite( "\4" . "\0\0\0\x19" .
               "\2" . "\3" . "\1" . "\x01" . "1" .
                             "\1" . "\x07" . "bounced" .
                             "\1" . "\x09" . "10 metres" );

wait_for { defined $howhigh };

is( $howhigh, "10 metres", '$howhigh is 10 metres after MSG_EVENT' );

# Check it said MSG_OK
$expect = "\x80" . "\0\0\0\1" .
          "\0";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_OK' );

my $colour;

$ballproxy->get_property(
   property => "colour",
   on_value => sub { $colour = shift },
   on_error  => sub { die "Test died early - $_[0]" },
);

# MSG_GETPROP
$expect = "\5" . "\0\0\0\x0d" .
          "\2" . "\2" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "colour";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_GETPROP' );

# MSG_RESULT
$S2->syswrite( "\x82" . "\0\0\0\5" .
               "\1" . "\x03" . "red" );

wait_for { defined $colour };

is( $colour, "red", '$colour is red' );

$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_error => sub { die "Test died early - $_[0]" },
);

# MSG_SETPROP
$expect = "\6" . "\0\0\0\x13" .
          "\2" . "\3" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "colour" .
                        "\1" . "\x04" . "blue";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_SETPROP' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\1" .
               "\0" );

$ballproxy->watch_property(
   property => "colour",
   on_change => sub { 
      my ( $obj, $prop, $how, @value ) = @_;
      $colour = $value[0];
} );

# MSG_WATCH
$expect = "\7" . "\0\0\0\x0f" .
          "\2" . "\3" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "colour" .
                        "\1" . "\x00";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_WATCH' );

# MSG_WATCHING
$S2->syswrite( "\x84" . "\0\0\0\x0a" .
               "\1" . "\x08" . "12345678" );



# We can't easily wait_for anything here... so we'll get on with the next
# thing and check both afterwards

# MSG_EVENT
$S2->syswrite( "\x09" . "\0\0\0\x17" .
               "\2" . "\4" . "\1" . "\x01" . "1" .
                             "\1" . "\x06" . "colour" .
                             "\1" . "\x01" . "1" .
                             "\1" . "\x05" . "green" );

undef $colour;
wait_for { defined $colour };

is( $colour, "green", '$colour is green after MSG_UPDATE' );
