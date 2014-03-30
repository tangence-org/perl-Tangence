#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2013 -- leonerd@leonerd.org.uk

package Tangence::Message;

use strict;
use warnings;

# Currently depends on atleast Perl 5.10.0 to provide the > format modifier
# for pack, to specify big-endian integers. If this code can be modified, this
# restriction could be listed.
use 5.010; 

our $VERSION = '0.18';

use Carp;

use Tangence::Constants;

use Tangence::Class;
use Tangence::Meta::Method;
use Tangence::Meta::Event;
use Tangence::Meta::Property;
use Tangence::Meta::Argument;
use Tangence::Struct;
use Tangence::Type;

use Tangence::Object;

use Encode qw( encode_utf8 decode_utf8 );
use List::Util qw( pairmap );
use Scalar::Util qw( weaken blessed );

# Normally we don't care about hash key order. But, when writing test scripts
# that will assert on the serialisation bytes, we do. Setting this to some
# true value will sort keys first
our $SORT_HASH_KEYS = 0;

use constant TYPE_ANY      => Tangence::Type->new( "any" );
use constant TYPE_INT      => Tangence::Type->new( "int" );
use constant TYPE_STR      => Tangence::Type->new( "str" );
use constant TYPE_LIST_ANY => Tangence::Type->new( list => TYPE_ANY );
use constant TYPE_LIST_STR => Tangence::Type->new( list => TYPE_STR );
use constant TYPE_DICT_ANY => Tangence::Type->new( dict => TYPE_ANY );

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
      elsif( $num == DATAMETA_STRUCT ) {
         $self->unpackmeta_struct;
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
   my ( $d, $subtype ) = @_;

   defined $d or croak "cannot pack_int(undef)";
   ref $d and croak "$d is not a number";
   $subtype ||= _best_int_type_for( $d );
   $self->_pack_leader( DATA_NUMBER, $subtype );
   $self->{record} .= pack( $pack_int_format{$subtype}[0], $d );
   return $self;
}

sub unpack_int
{
   my $self = shift;
   my ( $subtype ) = @_;
   my ( $type, $num ) = $self->_unpack_leader();

   $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
   exists $pack_int_format{$num} or croak "Expected an integer subtype but got $num";
   !$subtype or $subtype == $num or croak "Expected integer subtype $subtype, got $num";
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

sub pack_obj
{
   my $self = shift;
   my ( $d ) = @_;

   my $stream = $self->{stream};

   if( !defined $d ) {
      $self->_pack_leader( DATA_OBJECT, 0 );
   }
   elsif( blessed $d and $d->isa( "Tangence::Object" ) ) {
      my $id = $d->id;
      my $preamble = "";

      $d->{destroyed} and croak "Cannot pack destroyed object $d";

      $self->packmeta_construct( $d ) unless $stream->peer_hasobj->{$id};

      $self->_pack_leader( DATA_OBJECT, 4 );
      $self->{record} .= pack( "N", $id );
   }
   elsif( blessed $d and $d->isa( "Tangence::ObjectProxy" ) ) {
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
   $member_type->pack_value( $self, $_ ) for @$list;

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
      push @a, $member_type->unpack_value( $self );
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
   $self->pack_str( $_ ) and $member_type->pack_value( $self, $dict->{$_} ) for @keys;

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
      my $key = $self->unpack_str();
      $h{$key} = $member_type->unpack_value( $self );
   }
   return \%h;
}

sub pack_record
{
   my $self = shift;
   my ( $rec, $struct ) = @_;

   my $stream = $self->{stream};

   $struct ||= eval { Tangence::Struct->for_perlname( ref $rec ) } or
      croak "No struct for " . ref $rec;

   $self->packmeta_struct( $struct ) unless $stream->peer_hasstruct->{$struct->perlname};

   my @fields = $struct->fields;
   $self->_pack_leader( DATA_RECORD, scalar @fields );
   $self->pack_int( $stream->peer_hasstruct->{$struct->perlname}->[1] );
   foreach my $field ( @fields ) {
      my $fieldname = $field->name;
      $field->type->pack_value( $self, $rec->$fieldname );
   }

   return $self;
}

sub unpack_record
{
   my $self = shift;
   my ( $struct ) = @_;

   my $stream = $self->{stream};

   my ( $type, $num ) = $self->_unpack_leader();
   $type == DATA_RECORD or croak "Expected to unpack a record but did not find one";

   my $structid = $self->unpack_int();
   my $got_struct = $stream->message_state->{id2struct}{$structid};
   if( !$struct ) {
      $struct = $got_struct;
   }
   else {
      $struct->name eq $got_struct->name or
         croak "Expected to unpack a ".$struct->name." but found ".$got_struct->name;
   }

   $num == $struct->fields or croak "Expected ".$struct->name." to unpack from ".(scalar $struct->fields)." fields";

   my %values;
   foreach my $field ( $struct->fields ) {
      $values{$field->name} = $field->type->unpack_value( $self );
   }

   return $struct->perlname->new( %values );
}

sub packmeta_construct
{
   my $self = shift;
   my ( $obj ) = @_;

   my $stream = $self->{stream};

   my $class = $obj->class;
   my $id    = $obj->id;

   $self->packmeta_class( $class ) unless $stream->peer_hasclass->{$class->perlname};

   my $smashkeys = $class->smashkeys;

   $self->_pack_leader( DATA_META, DATAMETA_CONSTRUCT );
   $self->pack_int( $id );
   $self->pack_int( $stream->peer_hasclass->{$class->perlname}->[2] );

   my $smasharr = [];

   if( @$smashkeys ) {
      my $smashdata = $obj->smash( $smashkeys );
      $smasharr = [ map { $smashdata->{$_} } @$smashkeys ];

      for my $prop ( @$smashkeys ) {
         $stream->_install_watch( $obj, $prop );
      }
   }

   TYPE_LIST_ANY->pack_value( $self, $smasharr );

   weaken( my $weakstream = $stream );
   $stream->peer_hasobj->{$id} = $obj->subscribe_event( 
      destroy => sub { $weakstream->object_destroyed( @_ ) if $weakstream },
   );
}

sub unpackmeta_construct
{
   my $self = shift;

   my $stream = $self->{stream};

   my $id = $self->unpack_int();
   my $classid = $self->unpack_int();
   my $class = $stream->message_state->{id2class}{$classid};
   my $smasharr = TYPE_LIST_ANY->unpack_value( $self );

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

   my @superclasses = grep { $_->name ne "Tangence.Object" } $class->direct_superclasses;

   $stream->peer_hasclass->{$_->perlname} or $self->packmeta_class( $_ ) for @superclasses;

   $self->_pack_leader( DATA_META, DATAMETA_CLASS );

   my $smashkeys = $class->smashkeys;

   my $classid = ++$stream->message_state->{next_classid};

   $self->pack_str( $class->name );
   $self->pack_int( $classid );
   my $classrec = Tangence::Struct::Class->new(
      methods => {
         pairmap {
            $a => Tangence::Struct::Method->new(
               arguments => [ map { $_->type->sig } $b->arguments ],
               returns   => ( $b->ret ? $b->ret->sig : "" ),
            )
         } %{ $class->direct_methods }
      },
      events => {
         pairmap {
            $a => Tangence::Struct::Event->new(
               arguments => [ map { $_->type->sig } $b->arguments ],
            )
         } %{ $class->direct_events }
      },
      properties => {
         pairmap {
            $a => Tangence::Struct::Property->new(
               dimension => $b->dimension,
               type      => $b->type->sig,
               smashed   => $b->smashed,
            )
         } %{ $class->direct_properties }
      },
      superclasses => [ map { $_->name } @superclasses ],
   );
   $self->pack_any( $classrec );

   TYPE_LIST_STR->pack_value( $self, $smashkeys );

   $stream->peer_hasclass->{$class->perlname} = [ $class, $smashkeys, $classid ];
}

sub unpackmeta_class
{
   my $self = shift;

   my $stream = $self->{stream};

   my $name = $self->unpack_str();
   my $classid = $self->unpack_int();
   my $classrec = $self->unpack_any();

   my $class = Tangence::Meta::Class->new( name => $name );
   $class->define(
      methods => { 
         pairmap {
            $a => Tangence::Meta::Method->new(
               class     => $class,
               name      => $a,
               ret       => $b->returns ? Tangence::Type->new_from_sig( $b->returns )
                                        : undef,
               arguments => [ map {
                  Tangence::Meta::Argument->new(
                     type => Tangence::Type->new_from_sig( $_ ),
                  )
               } @{ $b->arguments } ],
            )
         } %{ $classrec->methods }
      },

      events => {
         pairmap {
            $a => Tangence::Meta::Event->new(
               class     => $class,
               name      => $a,
               arguments => [ map {
                  Tangence::Meta::Argument->new(
                     type => Tangence::Type->new_from_sig( $_ ),
                  )
               } @{ $b->arguments } ],
            )
         } %{ $classrec->events }
      },

      properties => {
         pairmap {
            $a => Tangence::Meta::Property->new(
               class     => $class,
               name      => $a,
               dimension => $b->dimension,
               type      => Tangence::Type->new_from_sig( $b->type ),
               smashed   => $b->smashed,
            )
         } %{ $classrec->properties }
      },

      superclasses => do {
         my @superclasses = map {
            ( my $perlname = $_ ) =~ s/\./::/g;
            $stream->peer_hasclass->{$perlname}->[3] or croak "Unrecognised class $perlname";
         } @{ $classrec->superclasses };

         @superclasses ? \@superclasses : [ Tangence::Class->for_name( "Tangence.Object" ) ]
      },
   );

   my $perlname = $class->perlname;

   my $smashkeys = TYPE_LIST_STR->unpack_value( $self );

   $stream->peer_hasclass->{$perlname} = [ $class, $smashkeys, $classid, $class ];
   if( defined $classid ) {
      $stream->message_state->{id2class}{$classid} = $perlname;
   }
}

sub packmeta_struct
{
   my $self = shift;
   my ( $struct ) = @_;

   my $stream = $self->{stream};

   $self->_pack_leader( DATA_META, DATAMETA_STRUCT );

   my @fields = $struct->fields;

   my $structid = ++$stream->message_state->{next_structid};
   $self->pack_str( $struct->name );
   $self->pack_int( $structid );
   TYPE_LIST_STR->pack_value( $self, [ map { $_->name } @fields ] );
   TYPE_LIST_STR->pack_value( $self, [ map { $_->type->sig } @fields ] );

   $stream->peer_hasstruct->{$struct->perlname} = [ $struct, $structid ];
}

sub unpackmeta_struct
{
   my $self = shift;

   my $stream = $self->{stream};

   my $name     = $self->unpack_str();
   my $structid = $self->unpack_int();
   my $names    = TYPE_LIST_STR->unpack_value( $self );
   my $types    = TYPE_LIST_STR->unpack_value( $self );

   my $struct = Tangence::Struct->new( name => $name );
   if( !$struct->defined ) {
      $struct->define(
         fields => [
            map { $names->[$_] => $types->[$_] } 0 .. $#$names
         ]
      );
   }

   $stream->peer_hasstruct->{$struct->perlname} = [ $struct, $structid ];
   $stream->message_state->{id2struct}{$structid} = $struct;
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
   elsif( blessed $d and $d->isa( "Tangence::Object" ) || $d->isa( "Tangence::ObjectProxy" ) ) {
      $self->pack_obj( $d );
   }
   elsif( my $struct = eval { Tangence::Struct->for_perlname( ref $d ) } ) {
      $self->pack_record( $d, $struct );
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

   my $stream = $self->{stream};

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
   elsif( $type == DATA_RECORD ) {
      return $self->unpack_record( undef );
   }
   else {
      croak "Do not know how to unpack record of type $type";
   }
}

sub pack_all_sametype
{
   my $self = shift;
   my $type = shift;

   $type->pack_value( $self, $_ ) for @_;

   return $self;
}

sub unpack_all_sametype
{
   my $self = shift;
   my ( $type ) = @_;
   my @data;
   push @data, $type->unpack_value( $self ) while length $self->{record};

   return @data;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
