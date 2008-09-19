#!/usr/bin/perl -w

use strict;

use Test::More tests => 6;
use Test::HexString;
use IO::Async::Test;
use IO::Async::Loop;

use Tangence::Constants;

my $loop = IO::Async::Loop->new();
testing_loop( $loop );

my ( $S1, $S2 ) = $loop->socketpair() or die "Cannot create socket pair - $!";

my @calls;
my $stream = Testing::Stream->new(
   handle => $S1,
);

ok( defined $stream, 'defined $stream' );
isa_ok( $stream, "Tangence::Stream", '$stream isa Tangence::Stream' );

$loop->add( $stream );

my $response;
$stream->request(
   request => [ MSG_CALL, 1, "method" ],
   on_response => sub { $response = $_[0] },
);

my $expect;
$expect = "\1" . "\0\0\0\x09" .
          "\x21" . "1" .
          "\x26" . "method";

my $serverstream;

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, 'serverstream after initial MSG_CALL' );

$S2->syswrite( "\x82" . "\0\0\0\x09" .
               "\x28" . "response" );

wait_for { defined $response };

is_deeply( $response, [ MSG_RESULT, "response" ], '$response to initial call' );

$S2->syswrite( "\x04" . "\0\0\0\x08" .
               "\x21" . "1" .
               "\x25" . "event" );

wait_for { @calls };

my $c = shift @calls;

is_deeply( $c->[2], [ "1", "event" ], '$call data after MSG_EVENT' );

$c->[0]->respond( $c->[1], [ MSG_OK ] );

$expect = "\x80" . "\0\0\0\0";

$serverstream = "";

wait_for_stream { length $serverstream >= length $expect } $S2 => $serverstream;

is_hexstr( $serverstream, $expect, '$serverstream after response' );

package Testing::Stream;

use strict;
use base qw( Tangence::Stream );

sub handle_request_EVENT
{
   my $self = shift;
   my ( $token, @data ) = @_;

   push @calls, [ $self, $token, \@data ];
   return 1;
}

1;
