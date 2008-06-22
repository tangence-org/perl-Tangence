#!/usr/bin/perl -w

use strict;

use Test::More tests => 6;
use IO::Async::Test;
use IO::Async::Loop::IO_Poll;

use IO::Socket::UNIX;
use Socket qw( AF_UNIX SOCK_STREAM PF_UNSPEC );

use Tangence::Constants;

my $loop = IO::Async::Loop::IO_Poll->new();
testing_loop( $loop );

( my $S1, my $S2 ) = IO::Socket::UNIX->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) or
   die "Cannot create socket pair - $!";

my @calls;
my $stream = Testing::Stream->new(
   handle => $S1,
);

ok( defined $stream, 'defined $stream' );
ok( $stream->isa( "Tangence::Stream" ), '$stream isa Tangence::Stream' );

$loop->add( $stream );

my $response;
$stream->request(
   request => [ MSG_CALL, [ 1, "method" ] ],
   on_response => sub { $response = $_[0] },
);

my $expect;
$expect = "\1" . "\0\0\0\x0d" .
          "\2" . "\2" . "\1" . "\x01" . "1" .
                        "\1" . "\x06" . "method";

my $serverstream;

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is( $serverstream, $expect, 'serverstream after initial MSG_CALL' );

$S2->syswrite( "\x82" . "\0\0\0\x0c" .
               "\2" . "\1" . "\1" . "\x08" . "response" );

wait_for { defined $response };

is_deeply( $response, [ MSG_RESULT, [ "response" ] ], '$response to initial call' );

$S2->syswrite( "\x04" . "\0\0\0\x0c" .
               "\2" . "\2" . "\1" . "\x01" . "1" .
                             "\1" . "\x05" . "event" );

wait_for { @calls };

my $c = shift @calls;

is_deeply( $c->[2], [ "1", "event" ], '$call data after MSG_EVENT' );

$c->[0]->respond( $c->[1], [ MSG_OK ] );

$expect = "\x80" . "\0\0\0\1" .
          "\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is( $serverstream, $expect, '$serverstream after response' );

package Testing::Stream;

use strict;
use base qw( Tangence::Stream );

sub handle_request_EVENT
{
   my $self = shift;
   my ( $token, $data ) = @_;

   push @calls, [ $self, $token, $data ];
   return 1;
}

1;
