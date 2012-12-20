#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2012 -- leonerd@leonerd.org.uk

package Tangence::Message;

use strict;
use warnings;

# Currently depends on atleast Perl 5.10.0 to provide the > format modifier
# for pack, to specify big-endian integers. If this code can be modified, this
# restriction could be listed.
use 5.010; 

our $VERSION = '0.13';

use Carp;

use Tangence::Constants;

use Tangence::Meta::Type;

use Encode qw( encode_utf8 decode_utf8 );
use Scalar::Util qw( weaken );

# Normally we don't care about hash key order. But, when writing test scripts
# that will assert on the serialisation bytes, we do. Setting this to some
# true value will sort keys first
our $SORT_HASH_KEYS = 0;

use constant TYPE_ANY      => Tangence::Meta::Type->new( "any" );
use constant TYPE_INT      => Tangence::Meta::Type->new( "int" );
use constant TYPE_STR      => Tangence::Meta::Type->new( "str" );
use constant TYPE_LIST_ANY => Tangence::Meta::Type->new( list => TYPE_ANY );
use constant TYPE_LIST_STR => Tangence::Meta::Type->new( list => TYPE_STR );
use constant TYPE_DICT_ANY => Tangence::Meta::Type->new( dict => TYPE_ANY );

# It would be really useful to put this in List::Utils or somesuch
sub pairmap(&@)
{
   my $code = shift;
   return map { $code->( local $a = shift, local $b = shift ) } 0 .. @_/2-1;
}

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

sub _peek_leader_type
{
   my $self = shift;

   while(1) {
      length $self->{record} or croak "Ran out of bytes before finding a leader";

      my ( $typenum ) = unpack( "C", $self->{record} );
      my $type = $typenum >> 5;

      return $type unless $type == DATA_META;

      substr( $self->{record}, 0, 1, "" );

      my $num  = $typenum & 0x1f;
      if( $num == DATAMETA_CONSTRUCT ) {
         $self->unpackmeta_construct;
      }
      elsif( $num == DATAMETA_CLASS ) {
         $self->unpackmeta_class;
      }
      else {
         die sprintf("TODO: Data stream meta-operation 0x%02x", $num);
      }
   }
}

sub _unpack_leader
{
   my $self = shift;

   my $type = $self->_peek_leader_type;
   my ( $typenum ) = unpack( "C", $self->{record} );
   substr( $self->{record}, 0, 1, "" );

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

   return $type, $num;
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
   my ( $type, $num ) = $self->_unpack_leader();

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
   my ( $type, $num ) = $self->_unpack_leader();

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
   my ( $type, $num ) = $self->_unpack_leader();

   $type == DATA_STRING or croak "Expected to unpack a string but did not find one";
   length $self->{record} >= $num or croak "Can't pull $num bytes for string as there aren't enough";
   my $octets = substr( $self->{record}, 0, $num, "" );
   return decode_utf8( $octets );
}

# Temporary methods for null-terminated strings. Will be removed once we no
# longer support protocol version 0
sub pack_stringZ
{
   my $self = shift;
   $self->{record} .= pack( "Z*", $_[0] );
}

sub unpack_stringZ
{
   my $self = shift;
   my ( $string ) = unpack( "Z*", $self->{record} );
   substr( $self->{record}, 0, 1 + length $string, "" );
   return $string;
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

      $self->packmeta_construct( $d ) unless $stream->peer_hasobj->{$id};

      $self->_pack_leader( DATA_OBJECT, 4 );
      $self->{record} .= pack( "N", $id );
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
   my ( $type, $num ) = $self->_unpack_leader();

   my $stream = $self->{stream};

   $type == DATA_OBJECT or croak "Expected to unpack an object but did not find one";
   return undef unless $num;
   if( $num == 4 ) {
      my ( $id ) = unpack( "N", $self->{record} ); substr( $self->{record}, 0, 4, "" );
      return $stream->get_by_id( $id );
   }
   else {
      croak "Unexpected number of bits to encode an OBJECT";
   }
}

sub pack_list
{
   my $self = shift;
   my ( $list, $listtype ) = @_;

   ref $list eq "ARRAY" or croak "Cannot pack a list from non-ARRAY reference";
   my $member_type = $listtype->member_type;

   $self->_pack_leader( DATA_LIST, scalar @$list );
   $self->pack_typed( $member_type, $_ ) for @$list;

   return $self;
}

sub unpack_list
{
   my $self = shift;
   my ( $listtype ) = @_;

   my ( $type, $num ) = $self->_unpack_leader();
   $type == DATA_LIST or croak "Expected to unpack a list but did not find one";

   my $member_type = $listtype->member_type;
   my @a;
   foreach ( 1 .. $num ) {
      push @a, $self->unpack_typed( $member_type );
   }
   return \@a;
}

sub pack_dict
{
   my $self = shift;
   my ( $dict, $dicttype ) = @_;

   ref $dict eq "HASH" or croak "Cannot pack a dict from non-HASH reference";
   my $member_type = $dicttype->member_type;

   my @keys = keys %$dict;
   @keys = sort @keys if $SORT_HASH_KEYS;

   $self->_pack_leader( DATA_DICT, scalar @keys );
   if( $self->{stream}->_ver_tangence_strings ) {
      $self->pack_str( $_ ) and $self->pack_typed( $member_type, $dict->{$_} ) for @keys;
   }
   else {
      $self->pack_stringZ( $_ ) and $self->pack_typed( $member_type, $dict->{$_} ) for @keys;
   }

   return $self;
}

sub unpack_dict
{
   my $self = shift;
   my ( $dicttype ) = @_;

   my ( $type, $num ) = $self->_unpack_leader();
   $type == DATA_DICT or croak "Expected to unpack a dict but did not find one";

   my $member_type = $dicttype->member_type;
   my %h;
   foreach ( 1 .. $num ) {
      my $key;
      if( $self->{stream}->_ver_tangence_strings ) {
         $key = $self->unpack_str();
      }
      else {
         $key = $self->unpack_stringZ();
      }
      $h{$key} = $self->unpack_typed( $member_type );
   }
   return \%h;
}

sub packmeta_construct
{
   my $self = shift;
   my ( $obj ) = @_;

   my $stream = $self->{stream};

   my $class = $obj->_meta;
   my $id    = $obj->id;

   $self->packmeta_class( $class ) unless $stream->peer_hasclass->{$class->perlname};

   my $smashkeys = $class->smashkeys;

   $self->_pack_leader( DATA_META, DATAMETA_CONSTRUCT );
   if( $stream->_ver_class_idnums ) {
      $self->pack_int( $id );
      $self->pack_int( $stream->peer_hasclass->{$class->perlname}->[2] );
   }
   else {
      $self->{record} .= pack( "N", $id );
      if( $stream->_ver_tangence_strings ) {
         $self->pack_str( $class->perlname );
      }
      else {
         $self->pack_stringZ( $class->perlname );
      }
   }

   my $smasharr = [];

   if( @$smashkeys ) {
      my $smashdata = $obj->smash( $smashkeys );
      $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];

      for my $prop ( @$smashkeys ) {
         $stream->_install_watch( $obj, $prop );
      }
   }

   $self->pack_typed( TYPE_LIST_ANY, $smasharr );

   weaken( my $weakstream = $stream );
   $stream->peer_hasobj->{$id} = $obj->subscribe_event( 
      destroy => sub { $weakstream->object_destroyed( @_ ) if $weakstream },
   );
}

sub unpackmeta_construct
{
   my $self = shift;

   my $stream = $self->{stream};

   my $id;
   my $class;
   if( $stream->_ver_class_idnums ) {
      $id = $self->unpack_int();
      my $classid = $self->unpack_int();
      $class = $stream->message_state->{id2class}{$classid};
   }
   else {
      ( $id ) = unpack( "N", $self->{record} ); substr( $self->{record}, 0, 4, "" );
      if( $stream->_ver_tangence_strings ) {
         $class = $self->unpack_str();
      }
      else {
         $class = $self->unpack_stringZ();
      }
   }
   my $smasharr = $self->unpack_typed( TYPE_LIST_ANY );

   my $smashkeys = $stream->peer_hasclass->{$class}->[1];

   my $smashdata;
   $smashdata->{$smashkeys->[$_]} = $smasharr->[$_] for 0 .. $#$smasharr;

   $stream->make_proxy( $id, $class, $smashdata );
}

sub packmeta_class
{
   my $self = shift;
   my ( $class ) = @_;

   my $stream = $self->{stream};

   $self->_pack_leader( DATA_META, DATAMETA_CLASS );

   my $introspection = {
      methods    => { 
         pairmap {
            $a => { args => [ map { $_->sig } $b->argtypes ], ret => ( $b->ret ? $b->ret->sig : "" ) }
         } %{ $class->methods }
      },
      events     => {
         pairmap {
            $a => { args => [ map { $_->sig } $b->argtypes ] }
         } %{ $class->events }
      },
      properties => {
         pairmap {
            $a => { type => $b->type->sig, dim => $b->dimension, $b->smashed ? ( smash => 1 ) : () }
         } %{ $class->properties }
      },
      isa        => [
         grep { $_ ne "Tangence::Object" } $class->perlname, map { $_->perlname } $class->superclasses
      ],
   };

   my $smashkeys = $class->smashkeys;

   my $classid;
   if( $stream->_ver_class_idnums ) {
      $classid = ++$stream->message_state->{next_classid};
      $self->pack_str( $class->perlname );
      $self->pack_int( $classid );
   }
   else {
      if( $stream->_ver_tangence_strings ) {
         $self->pack_str( $class->perlname );
      }
      else {
         $self->pack_stringZ( $self->perlname );
      }
   }
   $self->pack_typed( TYPE_DICT_ANY, $introspection );
   $self->pack_typed( TYPE_LIST_STR, $smashkeys );

   $stream->peer_hasclass->{$class->perlname} = [ $introspection, $smashkeys, $classid ];
}

sub unpackmeta_class
{
   my $self = shift;

   my $stream = $self->{stream};

   my $class;
   my $classid;
   if( $stream->_ver_class_idnums ) {
      $class = $self->unpack_str();
      $classid = $self->unpack_int();
   }
   else {
      if( $stream->_ver_tangence_strings ) {
         $class = $self->unpack_str();
      }
      else {
         $class = $self->unpack_stringZ();
      }
   }
   my $introspection = $self->unpack_typed( TYPE_DICT_ANY );
   my $smashkeys     = $self->unpack_typed( TYPE_LIST_STR );

   foreach my $mdef ( values %{ $introspection->{methods} } ) {
      $_ = Tangence::Meta::Type->new_from_sig( $_ ) for @{ $mdef->{args} };
      length and $_ = Tangence::Meta::Type->new_from_sig( $_) for $mdef->{ret};
   }
   foreach my $edef ( values %{ $introspection->{events} } ) {
      $_ = Tangence::Meta::Type->new_from_sig( $_ ) for @{ $edef->{args} };
   }
   foreach my $pdef ( values %{ $introspection->{properties} } ) {
      $_ = Tangence::Meta::Type->new_from_sig( $_ ) for $pdef->{type};
   }

   $stream->peer_hasclass->{$class} = [ $introspection, $smashkeys, $classid ];
   if( defined $classid ) {
      $stream->message_state->{id2class}{$classid} = $class;
   }
}

# Used by pack_typed
sub pack_prim
{
   my $self = shift;
   my ( $d, $type ) = @_;

   my $sig = $type->sig;

   if( my $code = $self->can( "pack_$sig" ) ) {
      $code->( $self, $d );
   }
   elsif( exists $int_sigs{$sig} ) {
      ref $d and croak "$d is not a number";
      my $subtype = $int_sigs{$sig};
      $self->_pack_leader( DATA_NUMBER, $subtype );
      $self->{record} .= pack( $pack_int_format{$subtype}[0], $d );
   }
   else {
      croak "Unrecognised type signature $sig";
   }

   return $self;
}

# Used by unpack_typed
sub unpack_prim
{
   my $self = shift;
   my ( $type ) = @_;

   my $sig = $type->sig;

   if( my $code = $self->can( "unpack_$sig" ) ) {
      return $code->( $self );
   }
   elsif( exists $int_sigs{$sig} ) {
      my ( $type, $num ) = $self->_unpack_leader();

      $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
      $num == $int_sigs{$sig} or croak "Expected subtype $int_sigs{$sig} but got $num";
      my ( $n ) = unpack( $pack_int_format{$num}[0], $self->{record} );
      substr( $self->{record}, 0, $pack_int_format{$num}[1] ) = "";
      return $n;
   }
   else {
      croak "Unrecognised type signature $sig";
   }
}

sub pack_any
{
   my $self = shift;
   my ( $d ) = @_;

   my $stream = $self->{stream};

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
      $self->pack_list( $d, TYPE_LIST_ANY );
   }
   elsif( ref $d eq "HASH" ) {
      $self->pack_dict( $d, TYPE_DICT_ANY );
   }
   else {
      croak "Do not know how to pack a " . ref($d);
   }

   return $self;
}

sub unpack_any
{
   my $self = shift;

   my $type = $self->_peek_leader_type();

   if( $type == DATA_NUMBER ) {
      return $self->unpack_int();
   }
   if( $type == DATA_STRING ) {
      return $self->unpack_str();
   }
   elsif( $type == DATA_OBJECT ) {
      return $self->unpack_obj();
   }
   elsif( $type == DATA_LIST ) {
      return $self->unpack_list( TYPE_LIST_ANY );
   }
   elsif( $type == DATA_DICT ) {
      return $self->unpack_dict( TYPE_DICT_ANY );
   }
   else {
      croak "Do not know how to unpack record of type $type";
   }
}

sub pack_typed
{
   my $self = shift;
   my ( $type, $d ) = @_;

   my $code = $self->can( "pack_" . $type->aggregate ) or die "Unrecognised type aggregation " . $type->aggregate;
   return $code->( $self, $d, $type );
}

sub unpack_typed
{
   my $self = shift;
   my $type = shift;

   my $code = $self->can( "unpack_" . $type->aggregate ) or die "Unrecognised type aggregation " . $type->aggregate;
   return $code->( $self, $type );
}

sub pack_all_typed
{
   my $self = shift;
   my ( $types, @args ) = @_;

   $self->pack_typed( $_, shift @args ) for @$types;
   return $self;
}

sub unpack_all_typed
{
   my $self = shift;
   my ( $types ) = @_;

   return map { $self->unpack_typed( $_ ) } @$types;
}

sub pack_all_sametype
{
   my $self = shift;
   my $type = shift;

   $self->pack_typed( $type, $_ ) for @_;

   return $self;
}

sub unpack_all_sametype
{
   my $self = shift;
   my ( $type ) = @_;
   my @data;
   push @data, $self->unpack_typed( $type ) while length $self->{record};

   return @data;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
