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

sub default_value { "" }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;
   $message->pack_bool( $value );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;
   return $message->unpack_bool;
}

package
   Tangence::Type::Primitive::_integral;
use base qw( Tangence::Type::Primitive );

use constant SUBTYPE => undef;

sub default_value { 0 }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;
   $message->pack_int( $value, $self->SUBTYPE );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;
   return $message->unpack_int( $self->SUBTYPE );
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

sub default_value { "" }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;
   $message->pack_str( $value );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;
   return $message->unpack_str;
}

package
   Tangence::Type::Primitive::obj;
use base qw( Tangence::Type::Primitive );

sub default_value { undef }

sub pack_value
{
   my $self = shift;
   my ( $message, $value ) = @_;
   $message->pack_obj( $value );
}

sub unpack_value
{
   my $self = shift;
   my ( $message ) = @_;
   return $message->unpack_obj;
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
