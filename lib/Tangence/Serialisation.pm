package Tangence::Serialisation;

use strict;

use Tangence::Constants;

use Carp;

use Encode qw( encode_utf8 decode_utf8 );

# Normally we don't care about hash key order. But, when writing test scripts
# that will assert on the serialisation bytes, we do. Setting this to some
# true value will sort keys first
our $SORT_HASH_KEYS = 0;

sub _pack_leader
{
   my ( $type, $num ) = @_;

   if( $num < 0x1f ) {
      return pack( "C", ( $type << 5 ) | $num );
   }
   elsif( $num < 0x80 ) {
      return pack( "CC", ( $type << 5 ) | 0x1f, $num );
   }
   else {
      return pack( "CN", ( $type << 5 ) | 0x1f, $num | 0x80000000 );
   }
}

sub _unpack_leader
{
   my ( $typenum ) = unpack( "C", $_[0] );
   substr( $_[0], 0, 1, "" );

   my $type = $typenum >> 5;
   my $num  = $typenum & 0x1f;

   if( $num == 0x1f ) {
      ( $num ) = unpack( "C", $_[0] );

      if( $num < 0x80 ) {
         substr( $_[0], 0, 1, "" );
      }
      else {
         ( $num ) = unpack( "N", $_[0] );
         $num &= 0x7fffffff;
         substr( $_[0], 0, 4, "" );
      }
   }

   return ( $type, $num );
}

sub _unpack_meta
{
   my $self = shift;
   my $num = shift;

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

sub _unpack_leader_dometa
{
   my $self = shift;

   while(1) {
      length $_[0] or croak "Ran out of bytes before finding a leader";
      my ( $type, $num ) = _unpack_leader( $_[0] );
      return $type, $num unless $type == DATA_META;

      $self->_unpack_meta( $num, $_[0] );
   }
}

sub pack_data
{
   my $self = shift;
   my ( $d ) = @_;

   if( !defined $d ) {
      return _pack_leader( DATA_OBJECT, 0 );
   }
   elsif( !ref $d ) {
      return $self->pack_str( $d );
   }
   elsif( ref $d eq "ARRAY" ) {
      return _pack_leader( DATA_LIST, scalar @$d ) . join( "", map { $self->pack_data( $_ ) } @$d );
   }
   elsif( ref $d eq "HASH" ) {
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      return _pack_leader( DATA_DICT, scalar @keys ) . join( "", map { pack( "Z*", $_ ) . $self->pack_data( $d->{$_} ) } @keys );
   }
   elsif( eval { $d->isa( "Tangence::Object" ) } ) {
      my $id = $d->id;
      my $preamble = "";

      $d->{destroyed} and croak "Cannot pack destroyed object $d";

      if( !$self->{peer_hasobj}->{$id} ) {
         my $class = ref $d;

         my $smashkeys;

         if( !$self->{peer_hasclass}->{$class} ) {
            my $schema = $class->introspect;

            $preamble .= _pack_leader( DATA_META, DATAMETA_CLASS ) . pack( "Z*", $class ) . $self->pack_data( $schema );

            $smashkeys = [ keys %{ $class->smashkeys } ];

            @$smashkeys = sort @$smashkeys if $SORT_HASH_KEYS;
            $smashkeys = undef unless @$smashkeys;

            $preamble .= $self->pack_data( $smashkeys );

            $self->{peer_hasclass}->{$class} = [ $smashkeys ];
         }
         else {
            $smashkeys = $self->{peer_hasclass}->{$class}->[0];
         }

         $preamble .= _pack_leader( DATA_META, DATAMETA_CONSTRUCT ) . pack( "NZ*", $id, $class );

         my $smasharr;

         if( $smashkeys ) {
            my $smashdata = $d->smash( $smashkeys );
            $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];

            for my $prop ( @$smashkeys ) {
               $self->_install_watch( $d, $prop );
            }
         }

         $preamble .= $self->pack_data( $smasharr );

         $self->{peer_hasobj}->{$id} = $d->subscribe_event( "destroy", $self->{destroy_cb} );
      }

      return $preamble . _pack_leader( DATA_OBJECT, 4 ) . pack( "N", $d->id );
   }
   elsif( eval { $d->isa( "Tangence::ObjectProxy" ) } ) {
      return _pack_leader( DATA_OBJECT, 4 ) . pack( "N", $d->id );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }
}

sub unpack_data
{
   my $self = shift;

   my ( $type, $num ) = $self->_unpack_leader_dometa( $_[0] );

   if( $type == DATA_STRING ) {
      return $self->unpack_str( $_[0], $type, $num );
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

### New deep-typed interface. Will slowly replace the untyped 'pack_data'
### system so we don't mind temporary code duplication here

sub pack_bool
{
   my $self = shift;
   my ( $d ) = @_;
   return _pack_leader( DATA_NUMBER, $d ? DATANUM_BOOLTRUE : DATANUM_BOOLFALSE );
}

sub unpack_bool
{
   my $self = shift;
   my ( $type, $num ) = @_ > 1 ? @_[1,2] : $self->_unpack_leader_dometa( $_[0] );

   $type == DATA_NUMBER or croak "Expected to unpack a number(bool) but did not find one";
   $num == DATANUM_BOOLFALSE and return 0;
   $num == DATANUM_BOOLTRUE  and return 1;
   croak "Expected to find a DATANUM_BOOL subtype but got $num";
}

my %pack_int_format = (
   DATANUM_UINT8,  "C",
   DATANUM_SINT8,  "c",
   DATANUM_UINT16, "S>",
   DATANUM_SINT16, "s>",
   DATANUM_UINT32, "L>",
   DATANUM_SINT32, "l>",
   DATANUM_UINT64, "Q>",
   DATANUM_SINT64, "q>",
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

   ref $d and croak "$d is not a number";
   my $subtype = _best_int_type_for( $d );
   return _pack_leader( DATA_NUMBER, $subtype ) . pack( $pack_int_format{$subtype}, $d );
}

sub unpack_int
{
   my $self = shift;
   my ( $type, $num ) = @_ > 1 ? @_[1,2] : $self->_unpack_leader_dometa( $_[0] );

   $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
   exists $pack_int_format{$num} or croak "Expected an integer subtype but got $num";
   my ( $n ) = unpack( $pack_int_format{$num}, $_[0] );
   substr( $_[0], 0, length pack( $pack_int_format{$num}, 0 ), "" ); # TODO: Do this more efficiently
   return $n;
}

sub pack_str
{
   my $self = shift;
   my ( $d ) = @_;

   ref $d and croak "$d is not a string";
   my $octets = encode_utf8( $d );
   return _pack_leader( DATA_STRING, length($octets) ) . $octets;
}

sub unpack_str
{
   my $self = shift;
   my ( $type, $num ) = @_ > 1 ? @_[1,2] : $self->_unpack_leader_dometa( $_[0] );

   $type == DATA_STRING or croak "Expected to unpack a string but did not find one";
   length $_[0] >= $num or croak "Can't pull $num bytes for string as there aren't enough";
   my $octets = substr( $_[0], 0, $num, "" );
   return decode_utf8( $octets );
}

sub pack_typed
{
   my $self = shift;
   my ( $sig, $d ) = @_;

   if( my $code = $self->can( "pack_$sig" ) ) {
      return $code->( $self, $d );
   }
   elsif( exists $int_sigs{$sig} ) {
      ref $d and croak "$d is not a number";
      my $subtype = $int_sigs{$sig};
      return _pack_leader( DATA_NUMBER, $subtype ) . pack( $pack_int_format{$subtype}, $d );
   }
   else {
      print STDERR "TODO: Pack as $sig from $d\n";
      die;
   }
}

sub unpack_typed
{
   my $self = shift;
   my $sig = shift;

   if( my $code = $self->can( "unpack_$sig" ) ) {
      return $code->( $self, $_[0] );
   }
   elsif( exists $int_sigs{$sig} ) {
      my ( $type, $num ) = $self->_unpack_leader_dometa( $_[0] );

      $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
      $num == $int_sigs{$sig} or croak "Expected subtype $int_sigs{$sig} but got $num";
      my ( $n ) = unpack( $pack_int_format{$num}, $_[0] );
      substr( $_[0], 0, length pack( $pack_int_format{$num}, 0 ), "" ); # TODO: Do this more efficiently
      return $n;
   }
   else {
      print STDERR "TODO: Unpack as $sig\n";
      die;
   }
}

1;
