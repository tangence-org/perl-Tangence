#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011-2012 -- leonerd@leonerd.org.uk

package Tangence::Meta::Type;

use strict;
use warnings;

use Carp;

our $VERSION = '0.07';

=head1 NAME

C<Tangence::Meta::Type> - structure representing one C<Tangence> value type

=head1 DESCRIPTION

This data structure object represents information about a type, such as a
method or event argument, a method return value, or a property element type.

Due to their simple contents and immutable nature, these objects may be
implemented as singletons.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $type = Tangence::Meta::Type->new( $primitive )

Returns an instance to represent the given primitive type signature.

=head2 $type = Tangence::Meta::Type->new( $aggregate => $member_type )

Returns an instance to represent the given aggregation of the given type
instance.

=cut

sub new
{
   shift;
   return Tangence::Meta::Type::Primitive->new( $_[0] ) if @_ == 1;
   return Tangence::Meta::Type::List->new( $_[1] ) if @_ == 2 and $_[0] eq "list";
   return Tangence::Meta::Type::Dict->new( $_[1] ) if @_ == 2 and $_[0] eq "dict";
   die "TODO: @_";
}

=head2 $type = Tangence::Meta::Type->new_from_sig( $sig )

Parses the given full Tangence type signature and returns an instance to
represent it.

=cut

sub new_from_sig
{
   my $class = shift;
   my ( $sig ) = @_;

   $sig =~ m/^list\((.*)\)$/ and
      return Tangence::Meta::Type->new( list => $class->new_from_sig( $1 ) );

   $sig =~ m/^dict\((.*)\)$/ and
      return Tangence::Meta::Type->new( dict => $class->new_from_sig( $1 ) );

   return Tangence::Meta::Type->new( $sig );
}

=head1 ACCESSORS

=cut

=head2 $sig = $type->sig

Returns the Tangence type signature for the type.

=cut

package # noindex
   Tangence::Meta::Type::Primitive;
use base qw( Tangence::Meta::Type );

our %TYPES;

sub new
{
   my $class = shift;
   my ( $sig ) = @_;
   return $TYPES{$sig} ||= bless [ $sig ], $class;
}

sub sig
{
   my $self = shift;
   return $self->[0];
}

package # noindex
   Tangence::Meta::Type::List;
use base qw( Tangence::Meta::Type );

our %TYPES;

sub new
{
   my $class = shift;
   my ( $membertype ) = @_;
   return $TYPES{$membertype->sig} ||= bless [ $membertype ], $class;
}

sub membertype
{
   my $self = shift;
   return $self->[0];
}

sub sig
{
   my $self = shift;
   return "list(" . $self->membertype->sig . ")";
}

package # noindex
   Tangence::Meta::Type::Dict;
use base qw( Tangence::Meta::Type );

our %TYPES;

sub new
{
   my $class = shift;
   my ( $membertype ) = @_;
   return $TYPES{$membertype->sig} ||= bless [ $membertype ], $class;
}

sub membertype
{
   my $self = shift;
   return $self->[0];
}

sub sig
{
   my $self = shift;
   return "dict(" . $self->membertype->sig . ")";
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
