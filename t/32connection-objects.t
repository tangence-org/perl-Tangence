#!/usr/bin/perl -w

use strict;

use Test::More tests => 5;
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

my $bagproxy = $conn->get_by_id("1");

my $response;

$bagproxy->call(
   method => "pull_ball",
   args   => [ "red" ],
   on_response => sub { $response = shift },
);

my $expect;

# MSG_CALL
$expect = "\1" . "\0\0\0\x15" . 
          "\2" . "\3" . "\1" . "\x01" . "1" .
                        "\1" . "\x09" . "pull_ball" .
                        "\1" . "\x03" . "red";

my $clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL' );

# MSG_RESULT
$S2->syswrite( "\x82" . "\0\0\0\5" .
               "\4" . "\0\0\0\2" );

wait_for { defined $response };

is( $response->[0], MSG_RESULT, 'response[0] is MSG_RESULT' );
ok( ref $response->[1] && $response->[1]->isa( "Tangence::ObjectProxy" ), 'response[1] contains an ObjectProxy' );

my $ballproxy = $response->[1];

$bagproxy->call(
   method => "add_ball",
   args   => [ $ballproxy ],
   on_response => sub { $response = shift },
);

# MSG_CALL
$expect = "\1" . "\0\0\0\x14" . 
          "\2" . "\3" . "\1" . "\x01" . "1" .
                        "\1" . "\x08" . "add_ball" .
                        "\4" . "\0\0\0\2";

$clientstream = "";
wait_for_stream { length $clientstream >= length $expect } $S2 => $clientstream;

is_hexstr( $clientstream, $expect, 'client stream contains MSG_CALL with an ObjectProxy' );

$S2->syswrite( "\x82" . "\0\0\0\1" .
               "\0" );

undef $response;
wait_for { defined $response };

is_deeply( $response, [ MSG_RESULT, undef ], 'response is MSG_RESULT' );
