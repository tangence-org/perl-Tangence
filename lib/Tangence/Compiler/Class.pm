#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Compiler::Class;

use strict;
use warnings;

our $VERSION = '0.06';

=head1 NAME

C<Tangence::Compiler::Class> - structure representing one C<Tangence> class

=head1 DESCRIPTION

This data structure object stores information about one L<Tangence> class, as
parsed by L<Tangence::Compiler::Parser>. Once constructed, such objects are
immutable.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $class = Tangence::Compiler::Class->new( %args )

Returns a new instance initialised by the given arguments.

=over 8

=item name => STRING

Name of the class

=item methods => HASH

=item events => HASH

=item properties => HASH

Optional HASH references containing metadata about methods, events and
properties, as instances of L<Tangence::Compiler::Method>,
L<Tangence::Compiler::Event> or L<Tangence::Compiler::Property>.

=item superclasses => ARRAY

Optional ARRAY reference containing superclasses as
C<Tangence::Compiler::Class> references.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   $args{superclasses} ||= [];
   $args{methods}      ||= {};
   $args{events}       ||= {};
   $args{properties}   ||= {};
   bless \%args, $class;
}

=head1 ACCESSORS

=cut

=head2 $name = $class->name

Returns the name of the class

=cut

sub name
{
   my $self = shift;
   return $self->{name};
}

=head2 @superclasses = $class->direct_superclasses

Return the direct superclasses in a list of C<Tangence::Compiler::Class>
references.

=cut

sub direct_superclasses
{
   my $self = shift;
   return @{ $self->{superclasses} };
}

=head2 $methods = $class->direct_methods

Return the methods that this class directly defines (rather than inheriting
from superclasses) as a HASH reference mapping names to
L<Tangence::Compiler::Method> instances.

=cut

sub direct_methods
{
   my $self = shift;
   return $self->{methods};
}

=head2 $events = $class->direct_events

Return the events that this class directly defines (rather than inheriting
from superclasses) as a HASH reference mapping names to
L<Tangence::Compiler::Event> instances.

=cut

sub direct_events
{
   my $self = shift;
   return $self->{events};
}

=head2 $properties = $class->direct_properties

Return the properties that this class directly defines (rather than inheriting
from superclasses) as a HASH reference mapping names to
L<Tangence::Compiler::Property> instances.

=cut

sub direct_properties
{
   my $self = shift;
   return $self->{properties};
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
