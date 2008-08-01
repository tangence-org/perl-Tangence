#!/usr/bin/perl -w

use strict;

use Test::More tests => 22;
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

my $ballproxy = $conn->get_by_id("1");

my $result;

$ballproxy->call_method(
   method => "bounce",
   args   => [ "20 metres" ],
   on_result => sub { $result = shift },
);

my $expect;

# MSG_CALL
$expect = "\1" . "\0\0\0\x16" .
          "\1" . "\x01" . "1" .
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

my $error;
$ballproxy->call_method(
   method => "no_such_method",
   args   => [ 123 ],
   on_result => sub { die "Call returned a result - $_[0]" },
   on_error  => sub { $error = shift; },
);

# MSG_CALL
$expect = "\1" . "\0\0\0\x18" .
          "\1" . "\x01" . "1" .
          "\1" . "\x0e" . "no_such_method" .
          "\1" . "\x03" . "123";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL' );

# MSG_ERROR
$S2->syswrite( "\x81" . "\0\0\0\x21" .
               "\1" . "\x1f" . "No such method 'no_such_method'" );

wait_for { defined $error };

is( $error, "No such method 'no_such_method'", '$error after MSG_ERROR response' );

my $howhigh;
my $subbed;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub {
      my ( $obj, $event, @args ) = @_;
      $howhigh = $args[0];
   },
   on_subscribed => sub { $subbed = 1 },
);

# MSG_SUBSCRIBE
$expect = "\2" . "\0\0\0\x0c" .
          "\1" . "\x01" . "1" .
          "\1" . "\x07" . "bounced";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_SUBSCRIBE' );

# MSG_SUBSCRIBED
$S2->syswrite( "\x83" . "\0\0\0\0" );

wait_for { $subbed };

# MSG_EVENT
$S2->syswrite( "\4" . "\0\0\0\x17" .
               "\1" . "\x01" . "1" .
               "\1" . "\x07" . "bounced" .
               "\1" . "\x09" . "10 metres" );

wait_for { defined $howhigh };

is( $howhigh, "10 metres", '$howhigh is 10 metres after MSG_EVENT' );

# Check it said MSG_OK
$expect = "\x80" . "\0\0\0\0";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_OK' );

my $bounced = 0;
$ballproxy->subscribe_event(
   event => "bounced",
   on_fire => sub { $bounced = 1 }
);

# MSG_EVENT
$S2->syswrite( "\4" . "\0\0\0\x16" .
               "\1" . "\x01" . "1" .
               "\1" . "\x07" . "bounced" .
               "\1" . "\x08" . "5 metres" );

$clientstream = "";
wait_for_stream { $bounced } $S2 => $clientstream;

is( $howhigh, "5 metres", '$howhigh is orange after second MSG_EVENT' );
is( $bounced, 1, '$bounced is true after second MSG_EVENT' );

is_hexstr( $clientstream, "", '$client stream is empty after second subscribe' );

# MSG_OK
$expect = "\x80" . "\0\0\0\0";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_OK' );

my $colour;

$ballproxy->get_property(
   property => "colour",
   on_value => sub { $colour = shift },
);

# MSG_GETPROP
$expect = "\5" . "\0\0\0\x0b" .
          "\1" . "\x01" . "1" .
          "\1" . "\x06" . "colour";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_GETPROP' );

# MSG_RESULT
$S2->syswrite( "\x82" . "\0\0\0\5" .
               "\1" . "\x03" . "red" );

wait_for { defined $colour };

is( $colour, "red", '$colour is red' );

my $didset = 0;
$ballproxy->set_property(
   property => "colour",
   value    => "blue",
   on_done  => sub { $didset = 1 },
);

# MSG_SETPROP
$expect = "\6" . "\0\0\0\x11" .
          "\1" . "\x01" . "1" .
          "\1" . "\x06" . "colour" .
          "\1" . "\x04" . "blue";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_SETPROP' );

# MSG_OK
$S2->syswrite( "\x80" . "\0\0\0\0" );

wait_for { $didset };

my $watched;
$ballproxy->watch_property(
   property => "colour",
   on_change => sub { 
      my ( $obj, $prop, $how, @value ) = @_;
      $colour = $value[0];
   },
   on_watched => sub { $watched = 1 },
);

# MSG_WATCH
$expect = "\7" . "\0\0\0\x0d" .
          "\1" . "\x01" . "1" .
          "\1" . "\x06" . "colour" .
          "\1" . "\x00";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_WATCH' );

# MSG_WATCHING
$S2->syswrite( "\x84" . "\0\0\0\3" .
               "\1" . "\1" . "1" );

wait_for { $watched };

# MSG_UPDATE
$S2->syswrite( "\x09" . "\0\0\0\x15" .
               "\1" . "\x01" . "1" .
               "\1" . "\x06" . "colour" .
               "\1" . "\x01" . "1" .
               "\1" . "\x05" . "green" );

undef $colour;
wait_for { defined $colour };

is( $colour, "green", '$colour is green after MSG_UPDATE' );

# MSG_OK
$expect = "\x80" . "\0\0\0\0";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_OK' );

my $colourchanged = 0;
my $secondcolour;
$ballproxy->watch_property(
   property => "colour",
   on_change => sub {
      ( undef, undef, undef, $secondcolour ) = @_;
      $colourchanged = 1
   },
   want_initial => 1,
);

# MSG_GETPROP
$expect = "\5" . "\0\0\0\x0b" .
          "\1" . "\x01" . "1" .
          "\1" . "\x06" . "colour";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_GETPROP' );

# MSG_RESULT
$S2->syswrite( "\x82" . "\0\0\0\7" .
               "\1" . "\x05" . "green" );

wait_for { $colourchanged };

is( $secondcolour, "green", '$secondcolour is green after second watch' );

# MSG_UPDATE
$S2->syswrite( "\x09" . "\0\0\0\x16" .
               "\1" . "\x01" . "1" .
               "\1" . "\x06" . "colour" .
               "\1" . "\x01" . "1" .
               "\1" . "\x06" . "orange" );

$colourchanged = 0;
wait_for { $colourchanged };

is( $colour, "orange", '$colour is orange after second MSG_UPDATE' );
is( $colourchanged, 1, '$colourchanged is true after second MSG_UPDATE' );

# MSG_OK
$expect = "\x80" . "\0\0\0\0";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_OK' );
