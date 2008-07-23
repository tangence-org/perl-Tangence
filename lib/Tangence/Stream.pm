package Tangence::Stream;

use strict;

use base qw( IO::Async::Sequencer );

use Tangence::Constants;

use Carp;

use Encode qw( encode_utf8 decode_utf8 );

# A map from request types to method names
# Can't use => operator because it would quote the barewords on the left, but
# we want them as constants
my %REQ_METHOD = (
   MSG_CALL,        'handle_request_CALL',
   MSG_SUBSCRIBE,   'handle_request_SUBSCRIBE',
   MSG_UNSUBSCRIBE, 'handle_request_UNSUBSCRIBE',
   MSG_EVENT,       'handle_request_EVENT',
   MSG_GETPROP,     'handle_request_GETPROP',
   MSG_SETPROP,     'handle_request_SETPROP',
   MSG_WATCH,       'handle_request_WATCH',
   MSG_UNWATCH,     'handle_request_UNWATCH',
   MSG_UPDATE,      'handle_request_UPDATE',
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new(
      %args,
      on_read => \&on_read,
      marshall_request  => \&marshall_request,
      marshall_response => \&marshall_response,

      on_request => sub {
         my ( $self, $token, $req ) = @_;

         my ( $type, $data ) = @$req;

         if( my $method = $REQ_METHOD{$type} ) {
            if( $self->can( $method ) ) {
               $self->$method( $token, $data );
            }
            else {
               $self->respond( $token, [ MSG_ERROR, sprintf( "Cannot respond to request type 0x%02x", $type ) ] );
            }
         }
         else {
            $self->respond( $token, [ MSG_ERROR, sprintf( "Unrecognised request type 0x%02x", $type ) ] );
         }
      },
   );

   return $self;
}

sub marshall_request
{
   my $self = shift;
   my ( $req ) = @_;

   my ( $type, $data ) = @$req;

   my $record = $self->pack_data( $data );

   return pack( "CNa*", $type, length($record), $record );
}

sub marshall_response
{
   my $self = shift;
   my ( $resp ) = @_;

   my ( $type, $data ) = @$resp;

   my $record = $self->pack_data( $data );

   return pack( "CNa*", $type, length($record), $record );
}

sub pack_num
{
   my ( $num ) = @_;

   if( $num < 0x80 ) {
      return pack( "C", $num );
   }
   else {
      return pack( "N", $num | 0x80000000 );
   }
}

sub unpack_num
{
   my ( $num ) = unpack( "C", $_[0] );

   if( $num < 0x80 ) {
      substr( $_[0], 0, 1, "" );
      return $num;
   }

   ( $num ) = unpack( "N", $_[0] );
   substr( $_[0], 0, 4, "" );

   $num &= 0x7fffffff;

   return $num;
}

sub pack_data
{
   my $self = shift;
   my ( $d ) = @_;

   if( !defined $d ) {
      return pack( "c", 0 );
   }
   elsif( !ref $d ) {
      my $octets = encode_utf8( $d );
      return "\x01" . pack_num( length($octets) ) . $octets;
   }
   elsif( ref $d eq "ARRAY" ) {
      return "\x02" . pack_num( scalar @$d ) . join( "", map { $self->pack_data( $_ ) } @$d );
   }
   elsif( ref $d eq "HASH" ) {
      return "\x03" . pack_num( scalar keys %$d ) . join( "", map { pack( "Z*", $_ ) . $self->pack_data( $d->{$_} ) } keys %$d );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) } ) {
      return "\x04" . pack( "N", $d->id );
   }
   elsif( eval { $d->isa( "Tangence::ObjectProxy" ) } ) {
      return "\x04" . pack( "N", $d->id );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }
}

sub unpack_data
{
   my $self = shift;
   my $t = unpack( "c", $_[0] ); substr( $_[0], 0, 1, "" );

   if( $t == 0 ) {
      return undef;
   }
   elsif( $t == 1 ) {
      my ( $len ) = unpack_num( $_[0] );
      my $octets = substr( $_[0], 0, $len, "" );
      return decode_utf8( $octets );
   }
   elsif( $t == 2 ) {
      my ( $count ) = unpack_num( $_[0] );
      my @a;
      foreach ( 1 .. $count ) {
         push @a, $self->unpack_data( $_[0] );
      }
      return \@a;
   }
   elsif( $t == 3 ) {
      my ( $count ) = unpack_num( $_[0] );
      my %h;
      foreach ( 1 .. $count ) {
         my ( $key ) = unpack( "Z*", $_[0] ); substr( $_[0], 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_data( $_[0] );
      }
      return \%h;
   }
   elsif( $t == 4 ) {
      my ( $id ) = unpack( "N", $_[0] ); substr( $_[0], 0, 4, "" );
      return $self->get_by_id( $id );
   }
   else {
      croak "Do not know how to unpack record of type $t";
   }
}

sub on_read
{
   my $self = shift;
   my ( $buffref, $closed ) = @_;

   return 0 unless length $$buffref >= 5;

   my ( $type, $len ) = unpack( "CN", $$buffref );
   return 0 unless length $$buffref >= 5 + $len;

   substr( $$buffref, 0, 5, "" );
   my $record = substr( $$buffref, 0, $len, "" );

   my $data = $self->unpack_data( $record );

   if( $type < 0x80 ) {
      $self->incoming_request( [ $type, $data ] );
   }
   else {
      $self->incoming_response( [ $type, $data ] );
   }

   return 1;
}

1;
