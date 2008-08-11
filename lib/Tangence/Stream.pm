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

   MSG_GETROOT,     'handle_request_GETROOT',
   MSG_GETREGISTRY, 'handle_request_GETREGISTRY',
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

   $self->{peer_hasobj} = {}; # {$id} = 1
   $self->{peer_hasclass} = {}; # {$classname} = [\@smashkeys];

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

sub pack_typenum
{
   my ( $type, $num ) = @_;

   if( $num <= 0x1f ) {
      return pack( "C", ( $type << 5 ) | $num );
   }
   else {
      return pack( "C", ( $type << 5 ) | 0x1f ) . pack_num( $num );
   }
}

sub unpack_typenum
{
   my ( $typenum ) = unpack( "C", $_[0] );
   substr( $_[0], 0, 1, "" );

   my $type = $typenum >> 5;
   my $num  = $typenum & 0x1f;

   if( $num == 0x1f ) {
      $num = unpack_num( $_[0] );
   }

   return ( $type, $num );
}

sub pack_data
{
   my $self = shift;
   my ( $d ) = @_;

   if( !defined $d ) {
      return pack_typenum( DATA_OBJECT, 0 );
   }
   elsif( !ref $d ) {
      my $octets = encode_utf8( $d );
      return pack_typenum( DATA_STRING, length($octets) ) . $octets;
   }
   elsif( ref $d eq "ARRAY" ) {
      return pack_typenum( DATA_LIST, scalar @$d ) . join( "", map { $self->pack_data( $_ ) } @$d );
   }
   elsif( ref $d eq "HASH" ) {
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      return pack_typenum( DATA_DICT, scalar @keys ) . join( "", map { pack( "Z*", $_ ) . $self->pack_data( $d->{$_} ) } @keys );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) } ) {
      my $id = $d->id;
      my $preamble = "";

      if( !$self->{peer_hasobj}->{$id} ) {
         my $class = ref $d;

         my $smashkeys;

         if( !$self->{peer_hasclass}->{$class} ) {
            my $schema = $class->introspect;

            $preamble .= pack_typenum( DATA_META, DATAMETA_CLASS ) . pack( "Z*", $class ) . $self->pack_data( $schema );

            $smashkeys = [ keys %{ $class->autoprops } ];
            for my $prop ( @$smashkeys ) {
               $self->_install_watch( $d, $prop );
            }

            @$smashkeys = sort @$smashkeys if $SORT_HASH_KEYS;
            $smashkeys = undef unless @$smashkeys;

            $preamble .= $self->pack_data( $smashkeys );

            $self->{peer_hasclass}->{$class} = [ $smashkeys ];
         }
         else {
            $smashkeys = $self->{peer_hasclass}->{$class}->[0];
         }

         $preamble .= pack_typenum( DATA_META, DATAMETA_CONSTRUCT ) . pack( "NZ*", $id, $class );

         my $smasharr;

         if( $smashkeys ) {
            my $smashdata = $d->smash( $smashkeys );
            $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];
         }

         $preamble .= $self->pack_data( $smasharr );

         $self->{peer_hasobj}->{$id} = 1;
      }

      return $preamble . pack_typenum( DATA_OBJECT, 4 ) . pack( "N", $d->id );
   }
   elsif( eval { $d->isa( "Tangence::ObjectProxy" ) } ) {
      return pack_typenum( DATA_OBJECT, 4 ) . pack( "N", $d->id );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }
}

sub unpack_data
{
   my $self = shift;

   my ( $type, $num );
   
   while(1) {
      ( $type, $num ) = unpack_typenum( $_[0] );
      last unless $type == DATA_META;

      if( $num == DATAMETA_CONSTRUCT ) {
         my ( $id, $class ) = unpack( "NZ*", $_[0] ); substr( $_[0], 0, 5 + length $class, "" );
         my $smasharr = $self->unpack_data( $_[0] );

         my $smashkeys = $self->{peer_hasclass}->{$class}->[0];

         my $smashdata;
         $smashdata->{$smashkeys->[$_]} = $smasharr->[$_] for 0 .. $#$smasharr;

         $self->make_proxy( $id, $class, $smashdata );
      }
      elsif( $num == DATAMETA_CLASS ) {
         my ( $class ) = unpack( "Z*", $_[0] ); substr( $_[0], 0, 1 + length $class, "" );
         my $schema = $self->unpack_data( $_[0] );

         $self->make_schema( $class, $schema );

         my $smashkeys = $self->unpack_data( $_[0] );
         $self->{peer_hasclass}->{$class} = [ $smashkeys ];
      }
      else {
         die sprintf("TODO: Data stream meta-operation 0x%02x", $num);
      }
   }

   if( $type == DATA_STRING ) {
      my $octets = substr( $_[0], 0, $num, "" );
      return decode_utf8( $octets );
   }
   elsif( $type == DATA_LIST ) {
      my @a;
      foreach ( 1 .. $num ) {
         push @a, $self->unpack_data( $_[0] );
      }
      return \@a;
   }
   elsif( $type == DATA_DICT ) {
      my %h;
      foreach ( 1 .. $num ) {
         my ( $key ) = unpack( "Z*", $_[0] ); substr( $_[0], 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_data( $_[0] );
      }
      return \%h;
   }
   elsif( $type == DATA_OBJECT ) {
      return undef unless $num;
      if( $num == 4 ) {
         my ( $id ) = unpack( "N", $_[0] ); substr( $_[0], 0, 4, "" );
         return $self->get_by_id( $id );
      }
      else {
         croak "Unexpected number of bits to encode an OBJECT";
      }
   }
   else {
      croak "Do not know how to unpack record of type $type";
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
