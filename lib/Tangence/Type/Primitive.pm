#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013-2014 -- leonerd@leonerd.org.uk

package Tangence::Type::Primitive;

use strict;
use warnings;
use feature qw( switch );
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use base qw( Tangence::Type );

package
   Tangence::Type::Primitive::bool;
use base qw( Tangence::Type::Primitive );
use Carp;
use Tangence::Constants;

sub default_value { "" }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;

   $message->_pack_leader( DATA_NUMBER, $value ? DATANUM_BOOLTRUE : DATANUM_BOOLFALSE );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;

   my ( $type, $num ) = $message->_unpack_leader();

   $type == DATA_NUMBER or croak "Expected to unpack a number(bool) but did not find one";
   $num == DATANUM_BOOLFALSE and return 0;
   $num == DATANUM_BOOLTRUE  and return 1;
   croak "Expected to find a DATANUM_BOOL subtype but got $num";
}

package
   Tangence::Type::Primitive::_integral;
use base qw( Tangence::Type::Primitive );
use Carp;
use Tangence::Constants;

use constant SUBTYPE => undef;

sub default_value { 0 }

my %format = (
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

   if( $n < 0 ) {
      return DATANUM_SINT8  if $n >= -0x80;
      return DATANUM_SINT16 if $n >= -0x8000;
      return DATANUM_SINT32 if $n >= -0x80000000;
      return DATANUM_SINT64;
   }

   return DATANUM_UINT8  if $n <= 0xff;
   return DATANUM_UINT16 if $n <= 0xffff;
   return DATANUM_UINT32 if $n <= 0xffffffff;
   return DATANUM_UINT64;
}

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;

   defined $value or croak "cannot pack_int(undef)";
   ref $value and croak "$value is not a number";

   my $subtype = $self->SUBTYPE || _best_int_type_for( $value );
   $message->_pack_leader( DATA_NUMBER, $subtype );

   $message->_pack( pack( $format{$subtype}[0], $value ) );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;

   my ( $type, $num ) = $message->_unpack_leader();

   $type == DATA_NUMBER or croak "Expected to unpack a number but did not find one";
   exists $format{$num} or croak "Expected an integer subtype but got $num";

   if( my $subtype = $self->SUBTYPE ) {
      $subtype == $num or croak "Expected integer subtype $subtype, got $num";
   }

   my ( $n ) = unpack( $format{$num}[0], $message->_unpack( $format{$num}[1] ) );

   return $n;
}

package
   Tangence::Type::Primitive::u8;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_UINT8;

package
   Tangence::Type::Primitive::s8;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_SINT8;

package
   Tangence::Type::Primitive::u16;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_UINT16;

package
   Tangence::Type::Primitive::s16;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_SINT16;

package
   Tangence::Type::Primitive::u32;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_UINT32;

package
   Tangence::Type::Primitive::s32;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_SINT32;

package
   Tangence::Type::Primitive::u64;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_UINT64;

package
   Tangence::Type::Primitive::s64;
use base qw( Tangence::Type::Primitive::_integral );
use constant SUBTYPE => Tangence::Constants::DATANUM_SINT64;

package
   Tangence::Type::Primitive::int;
use base qw( Tangence::Type::Primitive::_integral );

package
   Tangence::Type::Primitive::str;
use base qw( Tangence::Type::Primitive );
use Carp;
use Encode qw( encode_utf8 decode_utf8 );
use Tangence::Constants;

sub default_value { "" }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;

   defined $value or croak "cannot pack_str(undef)";
   ref $value and croak "$value is not a string";
   my $octets = encode_utf8( $value );
   $message->_pack_leader( DATA_STRING, length($octets) );
   $message->_pack( $octets );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;

   my ( $type, $num ) = $message->_unpack_leader();

   $type == DATA_STRING or croak "Expected to unpack a string but did not find one";
   my $octets = $message->_unpack( $num );
   return decode_utf8( $octets );
}

package
   Tangence::Type::Primitive::obj;
use base qw( Tangence::Type::Primitive );
use Carp;
use Scalar::Util qw( blessed );
use Tangence::Constants;

sub default_value { undef }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;

   my $stream = $message->stream;

   if( !defined $value ) {
      $message->_pack_leader( DATA_OBJECT, 0 );
   }
   elsif( blessed $value and $value->isa( "Tangence::Object" ) ) {
      my $id = $value->id;
      my $preamble = "";

      $value->{destroyed} and croak "Cannot pack destroyed object $value";

      $message->packmeta_construct( $value ) unless $stream->peer_hasobj->{$id};

      $message->_pack_leader( DATA_OBJECT, 4 );
      $message->_pack( pack( "N", $id ) );
   }
   elsif( blessed $value and $value->isa( "Tangence::ObjectProxy" ) ) {
      $message->_pack_leader( DATA_OBJECT, 4 );
      $message->_pack( pack( "N", $value->id ) );
   }
   else {
      croak "Do not know how to pack a " . ref($value);
   }
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;

   my ( $type, $num ) = $message->_unpack_leader();

   my $stream = $message->stream;

   $type == DATA_OBJECT or croak "Expected to unpack an object but did not find one";
   return undef unless $num;
   if( $num == 4 ) {
      my ( $id ) = unpack( "N", $message->_unpack( 4 ) );
      return $stream->get_by_id( $id );
   }
   else {
      croak "Unexpected number of bits to encode an OBJECT";
   }
}

package
   Tangence::Type::Primitive::any;
use base qw( Tangence::Type::Primitive );

sub default_value { undef }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;
   $message->pack_any( $value );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;
   return $message->unpack_any;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
