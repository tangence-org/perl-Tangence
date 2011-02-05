#!/usr/bin/perl -w

use strict;

use Test::More tests => 10;
use Test::HexString;

use Tangence::Constants;

my @calls;
my $written = "";
my $stream = Testing::Stream->new();

ok( defined $stream, 'defined $stream' );
isa_ok( $stream, "Tangence::Stream", '$stream isa Tangence::Stream' );

{
   my $message = Tangence::Message->new( $stream, MSG_CALL );
   $message->pack_int( 1 );
   $message->pack_str( "method" );

   my $response;
   $stream->request(
      request => $message,
      on_response => sub { $response = $_[0] },
   );

   my $expect = "\1" . "\0\0\0\x09" .
                "\x02" . "\x01" .
                "\x26" . "method";

   is_hexstr( $written, $expect, '$written after initial MSG_CALL' );
   $written = "";

   my $read = "\x82" . "\0\0\0\x09" .
              "\x28" . "response";

   $stream->tangence_readfrom( $read );

   is( length $read, 0, '$read completely consumed from response' );

   is( $response->type, MSG_RESULT, '$response->type to initial call' );
   is( $response->unpack_str, "response", '$response->unpack_str to initial call' );
}

{
   my $read = "\x04" . "\0\0\0\x08" .
              "\x02" . "\x01" .
              "\x25" . "event";

   $stream->tangence_readfrom( $read );

   is( length $read, 0, '$read completely consumed from event' );

   my $c = shift @calls;

   is( $c->[2]->unpack_int, 1, '$message->unpack_int after MSG_EVENT' );
   is( $c->[2]->unpack_str, "event", '$message->unpack_str after MSG_EVENT' );

   my $message = Tangence::Message->new( $stream, MSG_OK );
   $c->[0]->respond( $c->[1], $message );

   my $expect = "\x80" . "\0\0\0\0";

   is_hexstr( $written, $expect, '$written after response' );
}

package Testing::Stream;

use strict;
use base qw( Tangence::Stream );

sub new
{
   return bless {}, shift;
}

sub tangence_write
{
   my $self = shift;
   $written .= $_[0];
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $token, $message ) = @_;

   push @calls, [ $self, $token, $message ];
   return 1;
}

1;
