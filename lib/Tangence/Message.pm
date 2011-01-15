#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Message;

use strict;
use warnings;

our $VERSION = '0.02';

use Carp;

use Tangence::Constants;

use Encode qw( encode_utf8 decode_utf8 );
use Scalar::Util qw( weaken );

# Normally we don't care about hash key order. But, when writing test scripts
# that will assert on the serialisation bytes, we do. Setting this to some
# true value will sort keys first
our $SORT_HASH_KEYS = 0;

sub new
{
   my $class = shift;
   my ( $stream, $type, $record ) = @_;

   $record = "" unless defined $record;

   return bless {
      stream => $stream,
      type   => $type,
      record => $record,
   }, $class;
}

sub try_new_from_bytes
{
   my $class = shift;
   my $stream = shift;

   return undef unless length $_[0] >= 5;

   my ( $type, $len ) = unpack( "CN", $_[0] );
   return 0 unless length $_[0] >= 5 + $len;

   substr( $_[0], 0, 5, "" );

   my $record = substr( $_[0], 0, $len, "" );

   return $class->new( $stream, $type, $record );
}

sub type
{
   my $self = shift;
   return $self->{type};
}

sub bytes
{
   my $self = shift;

   my $record = $self->{record};
   return pack( "CNa*", $self->{type}, length($record), $record );
}

sub _pack_leader
{
   my $self = shift;
   my ( $type, $num ) = @_;

   if( $num < 0x1f ) {
      $self->{record} .= pack( "C", ( $type << 5 ) | $num );
   }
   elsif( $num < 0x80 ) {
      $self->{record} .= pack( "CC", ( $type << 5 ) | 0x1f, $num );
   }
   else {
      $self->{record} .= pack( "CN", ( $type << 5 ) | 0x1f, $num | 0x80000000 );
   }
}

sub _unpack_leader
{
   my $self = shift;

   my ( $typenum ) = unpack( "C", $self->{record} );
   substr( $self->{record}, 0, 1, "" );

   my $type = $typenum >> 5;
   my $num  = $typenum & 0x1f;

   if( $num == 0x1f ) {
      ( $num ) = unpack( "C", $self->{record} );

      if( $num < 0x80 ) {
         substr( $self->{record}, 0, 1, "" );
      }
      else {
         ( $num ) = unpack( "N", $self->{record} );
         $num &= 0x7fffffff;
         substr( $self->{record}, 0, 4, "" );
      }
   }

   return ( $type, $num );
}

sub _unpack_meta
{
   my $self = shift;
   my $num = shift;

   my $stream = $self->{stream};

   if( $num == DATAMETA_CONSTRUCT ) {
      my ( $id, $class ) = unpack( "NZ*", $self->{record} ); substr( $self->{record}, 0, 5 + length $class, "" );
      my $smasharr = $self->unpack_typed( 'list(any)' );

      my $smashkeys = $stream->{peer_hasclass}->{$class}->[0];

      my $smashdata;
      $smashdata->{$smashkeys->[$_]} = $smasharr->[$_] for 0 .. $#$smasharr;

      $stream->make_proxy( $id, $class, $smashdata );
   }
   elsif( $num == DATAMETA_CLASS ) {
      my ( $class ) = unpack( "Z*", $self->{record} ); substr( $self->{record}, 0, 1 + length $class, "" );
      my $schema = $self->unpack_typed( 'dict(any)' );

      $stream->make_schema( $class, $schema );

      my $smashkeys = $self->unpack_typed( 'list(str)' );
      $stream->{peer_hasclass}->{$class} = [ $smashkeys ];
   }
   else {
      die sprintf("TODO: Data stream meta-operation 0x%02x", $num);
   }
}

sub _unpack_leader_dometa
{
   my $self = shift;

   while(1) {
      length $self->{record} or croak "Ran out of bytes before finding a leader";
      my ( $type, $num ) = $self->_unpack_leader();
      return $type, $num unless $type == DATA_META;

      $self->_unpack_meta( $num );
   }
}

sub pack_bool
{
   my $self = shift;
   my ( $d ) = @_;
   $self->_pack_leader( DATA_NUMBER, $d ? DATANUM_BOOLTRUE : DATANUM_BOOLFALSE );
   return $self;
}

sub unpack_bool
{
   my $self = shift;
   my ( $type, $num ) = @_ ? @_ : $self->_unpack_leader_dometa();

   $type == DATA_NUMBER or croak "Expected to unpack a number(bool) but did not find one";
   $num == DATANUM_BOOLFALSE and return 0;
   $num == DATANUM_BOOLTRUE  and return 1;
   croak "Expected to find a DATANUM_BOOL subtype but got $num";
}

my %pack_int_format = (
   DATANUM_UINT8,  [ "C",  1 ],
   DATANUM_SINT8,  [ "c",  1 ],
   DATANUM_UINT16, [ "S>", 2 ],
   DATANUM_SINT16, [ "s>", 2 ],
   DATANUM_UINT32, [ "L>", 4 ],
   DATANUM_SINT32, [ "l>", 4 ],
   DATANUM_UINT64, [ "Q>", 8 ],
   DATANUM_SINT64, [ "q>", 8 ],
);

my %int_sigs = (
   u8  => DATANUM_UINT8,
   s8  => DATANUM_SINT8,
   u16 => DATANUM_UINT16,
   s16 => DATANUM_SINT16,
   u32 => DATANUM_UINT32,
   s32 => DATANUM_SINT32,
   u64 => DATANUM_UINT64,
   s64 => DATANUM_SINT64,
);

sub _best_int_type_for
{
   my ( $n ) = @_;

   # TODO: Consider 64bit values

   if( $n < 0 ) {
      return DATANUM_SINT8  if $n >= -0x80;
      return DATANUM_SINT16 if $n >= -0x8000;
      return DATANUM_SINT32;
   }

   return DATANUM_UINT8  if $n <= 0xff;
   return DATANUM_UINT16 if $n <= 0xffff;
   return DATANUM_UINT32;
}

sub pack_int
{
   my $self = shift;
   my ( $d ) = @_;

   defined $d or croak "cannot pack_int(undef)";
   ref $d and croak "$d is not a number";
   my $subtype = _best_int_type_for( $d );
   $self->_pack_leader( DATA_NUMBER, $subtype );
   $self->{record} .= pack( $pack_int_format{$subtype}[0], $d );
   return $self;
}

sub unpack_int
{
   my $self = shift;
   my ( $type, $num ) = @_ ? @_ : $self->_unpack_leader_dometa();

   $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
   exists $pack_int_format{$num} or croak "Expected an integer subtype but got $num";
   my ( $n ) = unpack( $pack_int_format{$num}[0], $self->{record} );
   substr( $self->{record}, 0, $pack_int_format{$num}[1] ) = "";
   return $n;
}

sub pack_str
{
   my $self = shift;
   my ( $d ) = @_;

   defined $d or croak "cannot pack_str(undef)";
   ref $d and croak "$d is not a string";
   my $octets = encode_utf8( $d );
   $self->_pack_leader( DATA_STRING, length($octets) );
   $self->{record} .= $octets;
   return $self;
}

sub unpack_str
{
   my $self = shift;
   my ( $type, $num ) = @_ ? @_ : $self->_unpack_leader_dometa();

   $type == DATA_STRING or croak "Expected to unpack a string but did not find one";
   length $self->{record} >= $num or croak "Can't pull $num bytes for string as there aren't enough";
   my $octets = substr( $self->{record}, 0, $num, "" );
   return decode_utf8( $octets );
}

sub pack_obj
{
   my $self = shift;
   my ( $d ) = @_;

   my $stream = $self->{stream};

   if( !defined $d ) {
      $self->_pack_leader( DATA_OBJECT, 0 );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) } ) {
      my $id = $d->id;
      my $preamble = "";

      $d->{destroyed} and croak "Cannot pack destroyed object $d";

      if( !$stream->{peer_hasobj}->{$id} ) {
         my $class = ref $d;

         my $smashkeys;

         if( !$stream->{peer_hasclass}->{$class} ) {
            my $schema = $class->introspect;

            $self->_pack_leader( DATA_META, DATAMETA_CLASS );
            $self->{record} .= pack( "Z*", $class );
            $self->pack_typed( 'dict(any)', $schema );

            $smashkeys = [ keys %{ $class->smashkeys } ];

            @$smashkeys = sort @$smashkeys if $SORT_HASH_KEYS;

            $self->pack_typed( 'list(str)', $smashkeys );

            $stream->{peer_hasclass}->{$class} = [ $smashkeys ];
         }
         else {
            $smashkeys = $stream->{peer_hasclass}->{$class}->[0];
         }

         $self->_pack_leader( DATA_META, DATAMETA_CONSTRUCT );
         $self->{record} .= pack( "NZ*", $id, $class );

         my $smasharr = [];

         if( @$smashkeys ) {
            my $smashdata = $d->smash( $smashkeys );
            $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];

            for my $prop ( @$smashkeys ) {
               $stream->_install_watch( $d, $prop );
            }
         }

         $self->pack_typed( 'list(any)', $smasharr );

         weaken( my $weakstream = $stream );
         $stream->{peer_hasobj}->{$id} = $d->subscribe_event( 
            destroy => sub { $weakstream->object_destroyed( @_ ) },
         );
      }

      $self->_pack_leader( DATA_OBJECT, 4 );
      $self->{record} .= pack( "N", $d->id );
   }
   elsif( eval { $d->isa( "Tangence::ObjectProxy" ) } ) {
      $self->_pack_leader( DATA_OBJECT, 4 );
      $self->{record} .= pack( "N", $d->id );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }
   return $self;
}

sub unpack_obj
{
   my $self = shift;
   my ( $type, $num ) = @_ ? @_ : $self->_unpack_leader_dometa();

   my $stream = $self->{stream};

   return undef unless $num;
   if( $num == 4 ) {
      my ( $id ) = unpack( "N", $self->{record} ); substr( $self->{record}, 0, 4, "" );
      return $stream->get_by_id( $id );
   }
   else {
      croak "Unexpected number of bits to encode an OBJECT";
   }
}

sub pack_any
{
   my $self = shift;
   my ( $d ) = @_;

   if( !defined $d ) {
      $self->pack_obj( undef );
   }
   elsif( !ref $d ) {
      # TODO: We'd never choose to pack a number
      $self->pack_str( $d );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) or $d->isa( "Tangence::ObjectProxy" ) } ) {
      $self->pack_obj( $d );
   }
   elsif( ref $d eq "ARRAY" ) {
      $self->_pack_leader( DATA_LIST, scalar @$d );
      $self->pack_any( $_ ) for @$d;
   }
   elsif( ref $d eq "HASH" ) {
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      $self->_pack_leader( DATA_DICT, scalar @keys );
      $self->{record} .= pack( "Z*", $_ ) and $self->pack_any( $d->{$_} ) for @keys;
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }

   return $self;
}

sub unpack_any
{
   my $self = shift;

   my ( $type, $num ) = $self->_unpack_leader_dometa();

   if( $type == DATA_NUMBER ) {
      return $self->unpack_int( $type, $num );
   }
   if( $type == DATA_STRING ) {
      return $self->unpack_str( $type, $num );
   }
   elsif( $type == DATA_OBJECT ) {
      return $self->unpack_obj( $type, $num );
   }
   elsif( $type == DATA_LIST ) {
      my @a;
      foreach ( 1 .. $num ) {
         push @a, $self->unpack_any();
      }
      return \@a;
   }
   elsif( $type == DATA_DICT ) {
      my %h;
      foreach ( 1 .. $num ) {
         my ( $key ) = unpack( "Z*", $self->{record} ); substr( $self->{record}, 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_any();
      }
      return \%h;
   }
   else {
      croak "Do not know how to unpack record of type $type";
   }
}

sub pack_typed
{
   my $self = shift;
   my ( $sig, $d ) = @_;

   if( my $code = $self->can( "pack_$sig" ) ) {
      $code->( $self, $d );
   }
   elsif( exists $int_sigs{$sig} ) {
      ref $d and croak "$d is not a number";
      my $subtype = $int_sigs{$sig};
      $self->_pack_leader( DATA_NUMBER, $subtype );
      $self->{record} .= pack( $pack_int_format{$subtype}[0], $d );
   }
   elsif( $sig =~ m/^list\((.*)\)$/ ) {
      my $subtype = $1;
      ref $d eq "ARRAY" or croak "Cannot pack a list from non-ARRAY reference";
      $self->_pack_leader( DATA_LIST, scalar @$d );
      $self->pack_typed( $subtype, $_ ) for @$d;
   }
   elsif( $sig =~ m/^dict\((.*)\)$/ ) {
      my $subtype = $1;
      ref $d eq "HASH" or croak "Cannot pack a dict from non-HASH reference";
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      $self->_pack_leader( DATA_DICT, scalar @keys );
      $self->{record} .= pack( "Z*", $_ ) and $self->pack_typed( $subtype, $d->{$_} ) for @keys;
   }
   else {
      croak "Unrecognised type signature $sig";
   }

   return $self;
}

sub unpack_typed
{
   my $self = shift;
   my $sig = shift;

   if( my $code = $self->can( "unpack_$sig" ) ) {
      return $code->( $self );
   }
   elsif( exists $int_sigs{$sig} ) {
      my ( $type, $num ) = $self->_unpack_leader_dometa();

      $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
      $num == $int_sigs{$sig} or croak "Expected subtype $int_sigs{$sig} but got $num";
      my ( $n ) = unpack( $pack_int_format{$num}[0], $self->{record} );
      substr( $self->{record}, 0, $pack_int_format{$num}[1] ) = "";
      return $n;
   }
   elsif( $sig =~ m/^list\((.*)\)$/ ) {
      my $subtype = $1;
      my ( $type, $num ) = $self->_unpack_leader_dometa();

      $type == DATA_LIST or croak "Expected to unpack a list but did not find one";
      my @a;
      foreach ( 1 .. $num ) {
         push @a, $self->unpack_typed( $subtype );
      }
      return \@a;
   }
   elsif( $sig =~ m/^dict\((.*)\)$/ ) {
      my $subtype = $1;
      my ( $type, $num ) = $self->_unpack_leader_dometa();

      $type == DATA_DICT or croak "Expected to unpack a dict but did not find one";
      my %h;
      foreach ( 1 .. $num ) {
         my ( $key ) = unpack( "Z*", $self->{record} ); substr( $self->{record}, 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_typed( $subtype );
      }
      return \%h;
   }
   else {
      croak "Unrecognised type signature $sig";
   }
}

sub pack_all_typed
{
   my $self = shift;
   my ( $sigs, @args ) = @_;

   $self->pack_typed( $_, shift @args ) for @$sigs;
   return $self;
}

sub unpack_all_typed
{
   my $self = shift;
   my ( $sigs ) = @_;

   return map { $self->unpack_typed( $_ ) } @$sigs;
}

sub pack_all_sametype
{
   my $self = shift;
   my $sig = shift;

   $self->pack_typed( $sig, $_ ) for @_;

   return $self;
}

sub unpack_all_sametype
{
   my $self = shift;
   my ( $sig ) = @_;
   my @data;
   push @data, $self->unpack_typed( $sig ) while length $self->{record};

   return @data;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
