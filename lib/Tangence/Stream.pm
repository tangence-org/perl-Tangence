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

# Normally we don't care about hash key order. But, when writing test scripts
# that will assert on the serialisation bytes, we do. Setting this to some
# true value will sort keys first
our $SORT_HASH_KEYS = 0;

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

         my ( $type, @data ) = @$req;

         if( my $method = $REQ_METHOD{$type} ) {
            if( $self->can( $method ) ) {
               $self->$method( $token, @data );
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

   my ( $type, @data ) = @$req;

   my $record = "";
   $record .= $self->pack_data( $_ ) for @data;

   return pack( "CNa*", $type, length($record), $record );
}

sub marshall_response
{
   my $self = shift;
   my ( $resp ) = @_;

   my ( $type, @data ) = @$resp;

   my $record = "";
   $record .= $self->pack_data( $_ ) for @data;

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
      return chr(DATA_UNDEF);
   }
   elsif( !ref $d ) {
      my $octets = encode_utf8( $d );
      return chr(DATA_STRING) . pack_num( length($octets) ) . $octets;
   }
   elsif( ref $d eq "ARRAY" ) {
      return chr(DATA_LIST) . pack_num( scalar @$d ) . join( "", map { $self->pack_data( $_ ) } @$d );
   }
   elsif( ref $d eq "HASH" ) {
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      return chr(DATA_DICT) . pack_num( scalar @keys ) . join( "", map { pack( "Z*", $_ ) . $self->pack_data( $d->{$_} ) } @keys );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) } ) {
      return chr(DATA_OBJECT) . pack( "N", $d->id );
   }
   elsif( eval { $d->isa( "Tangence::ObjectProxy" ) } ) {
      return chr(DATA_OBJECT) . pack( "N", $d->id );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }
}

sub unpack_data
{
   my $self = shift;
   my $t = unpack( "c", $_[0] ); substr( $_[0], 0, 1, "" );

   if( $t == DATA_UNDEF ) {
      return undef;
   }
   elsif( $t == DATA_STRING ) {
      my ( $len ) = unpack_num( $_[0] );
      my $octets = substr( $_[0], 0, $len, "" );
      return decode_utf8( $octets );
   }
   elsif( $t == DATA_LIST ) {
      my ( $count ) = unpack_num( $_[0] );
      my @a;
      foreach ( 1 .. $count ) {
         push @a, $self->unpack_data( $_[0] );
      }
      return \@a;
   }
   elsif( $t == DATA_DICT ) {
      my ( $count ) = unpack_num( $_[0] );
      my %h;
      foreach ( 1 .. $count ) {
         my ( $key ) = unpack( "Z*", $_[0] ); substr( $_[0], 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_data( $_[0] );
      }
      return \%h;
   }
   elsif( $t == DATA_OBJECT ) {
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

   my @data;
   while( length $record ) {
      push @data, $self->unpack_data( $record );
   }

   if( $type < 0x80 ) {
      $self->incoming_request( [ $type, @data ] );
   }
   else {
      $self->incoming_response( [ $type, @data ] );
   }

   return 1;
}

1;
