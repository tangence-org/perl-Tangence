#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Meta::Property;

use strict;
use warnings;

our $VERSION = '0.08';

use Scalar::Util qw( weaken );

=head1 NAME

C<Tangence::Meta::Property> - structure representing one C<Tangence> property

=head1 DESCRIPTION

This data structure object stores information about one L<Tangence> class
property. Once constructed, such objects are immutable.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $property = Tangence::Meta::Property->new( %args )

Returns a new instance initialised by the given arguments.

=over 8

=item class => Tangence::Meta::Class

Reference to the containing class

=item name => STRING

Name of the property

=item dimension => INT

Dimension of the property, as one of the C<DIM_*> constants from
L<Tangence::Constants>.

=item type => STRING

String giving the type as a string.

=item smashed => BOOL

Optional. If true, marks that the property is smashed.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   my $self = bless \%args, $class;
   weaken $self->{class};
   return $self;
}

=head1 ACCESSORS

=cut

=head2 $class = $property->class

Returns the class the property is a member of

=cut

sub class
{
   my $self = shift;
   return $self->{class};
}

=head2 $name = $property->name

Returns the name of the class

=cut

sub name
{
   my $self = shift;
   return $self->{name};
}

=head2 $dimension = $property->dimension

Returns the dimension as one of the C<DIM_*> constants.

=cut

sub dimension
{
   my $self = shift;
   return $self->{dimension};
}

=head2 $type = $property->type

Returns the type as a string.

=cut

sub type
{
   my $self = shift;
   return $self->{type};
}

=head2 $smashed = $property->smashed

Returns true if the property is smashed.

=cut

sub smashed
{
   my $self = shift;
   return $self->{smashed};
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

