package Tangence::Message;

use strict;

use Tangence::Constants;

use Carp;

use Encode qw( encode_utf8 decode_utf8 );

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
      my $smasharr = $self->unpack_data();

      my $smashkeys = $stream->{peer_hasclass}->{$class}->[0];

      my $smashdata;
      $smashdata->{$smashkeys->[$_]} = $smasharr->[$_] for 0 .. $#$smasharr;

      $stream->make_proxy( $id, $class, $smashdata );
   }
   elsif( $num == DATAMETA_CLASS ) {
      my ( $class ) = unpack( "Z*", $self->{record} ); substr( $self->{record}, 0, 1 + length $class, "" );
      my $schema = $self->unpack_data();

      $stream->make_schema( $class, $schema );

      my $smashkeys = $self->unpack_data();
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

sub pack_data
{
   my $self = shift;
   my ( $d ) = @_;

   if( !defined $d ) {
      $self->pack_obj( undef );
   }
   elsif( !ref $d ) {
      $self->pack_str( $d );
   }
   elsif( ref $d eq "ARRAY" ) {
      $self->_pack_leader( DATA_LIST, scalar @$d );
      $self->pack_data( $_ ) for @$d;
   }
   elsif( ref $d eq "HASH" ) {
      my @keys = keys %$d;
      @keys = sort @keys if $SORT_HASH_KEYS;
      $self->_pack_leader( DATA_DICT, scalar @keys );
      $self->{record} .= pack( "Z*", $_ ) and $self->pack_data( $d->{$_} ) for @keys;
   }
   elsif( eval { $d->isa( "Tangence::Object" ) or $d->isa( "Tangence::ObjectProxy" ) } ) {
      $self->pack_obj( $d );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }

   return $self;
}

sub unpack_data
{
   my $self = shift;

   my ( $type, $num ) = $self->_unpack_leader_dometa();

   if( $type == DATA_STRING ) {
      return $self->unpack_str( $type, $num );
   }
   elsif( $type == DATA_LIST ) {
      my @a;
      foreach ( 1 .. $num ) {
         push @a, $self->unpack_data();
      }
      return \@a;
   }
   elsif( $type == DATA_DICT ) {
      my %h;
      foreach ( 1 .. $num ) {
         my ( $key ) = unpack( "Z*", $self->{record} ); substr( $self->{record}, 0, 1 + length $key, "" );
         $h{$key} = $self->unpack_data();
      }
      return \%h;
   }
   elsif( $type == DATA_OBJECT ) {
      return $self->unpack_obj( $type, $num );
   }
   else {
      croak "Do not know how to unpack record of type $type";
   }
}

sub pack_all_data
{
   my $self = shift;
   $self->pack_data( $_ ) for @_;

   return $self;
}

sub unpack_all_data
{
   my $self = shift;
   my @data;
   push @data, $self->unpack_data while length $self->{record};

   return @data;
}

### New deep-typed interface. Will slowly replace the untyped 'pack_data'
### system so we don't mind temporary code duplication here

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
   $self->_pack_leader( DATA_NUMBER, $subtype );
   $self->{record} .= pack( $pack_int_format{$subtype}, $d );
   return $self;
}

sub unpack_int
{
   my $self = shift;
   my ( $type, $num ) = @_ ? @_ : $self->_unpack_leader_dometa();

   $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
   exists $pack_int_format{$num} or croak "Expected an integer subtype but got $num";
   my ( $n ) = unpack( $pack_int_format{$num}, $self->{record} );
   substr( $self->{record}, 0, length pack( $pack_int_format{$num}, 0 ), "" ); # TODO: Do this more efficiently
   return $n;
}

sub pack_str
{
   my $self = shift;
   my ( $d ) = @_;

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
            $self->pack_data( $schema );

            $smashkeys = [ keys %{ $class->smashkeys } ];

            @$smashkeys = sort @$smashkeys if $SORT_HASH_KEYS;
            $smashkeys = undef unless @$smashkeys;

            $self->pack_data( $smashkeys );

            $stream->{peer_hasclass}->{$class} = [ $smashkeys ];
         }
         else {
            $smashkeys = $stream->{peer_hasclass}->{$class}->[0];
         }

         $self->_pack_leader( DATA_META, DATAMETA_CONSTRUCT );
         $self->{record} .= pack( "NZ*", $id, $class );

         my $smasharr;

         if( $smashkeys ) {
            my $smashdata = $d->smash( $smashkeys );
            $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];

            for my $prop ( @$smashkeys ) {
               $stream->_install_watch( $d, $prop );
            }
         }

         $self->pack_data( $smasharr );

         $stream->{peer_hasobj}->{$id} = $d->subscribe_event( "destroy", $stream->{destroy_cb} );
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
      $self->{record} .= pack( $pack_int_format{$subtype}, $d );
   }
   else {
      print STDERR "TODO: Pack as $sig from $d\n";
      die;
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
      my ( $n ) = unpack( $pack_int_format{$num}, $self->{record} );
      substr( $self->{record}, 0, length pack( $pack_int_format{$num}, 0 ), "" ); # TODO: Do this more efficiently
      return $n;
   }
   else {
      print STDERR "TODO: Unpack as $sig\n";
      die;
   }
}

1;
