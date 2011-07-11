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

=item props => HASH

Optional HASH references containing metadata about methods, events and
properties, as instances of L<Tangence::Compiler::Method>,
L<Tangence::Compiler::Event> or L<Tangence::Compiler::Property>.

=item supers => ARRAY

Optional ARRAY reference containing superclasses as
C<Tangence::Compiler::Class> references.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   $args{supers}  ||= [];
   $args{methods} ||= {};
   $args{events}  ||= {};
   $args{props}   ||= {};
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

=head2 @supers = $class->supers

Return the superclasses in a list of C<Tangence::Compiler::Class> references.

=cut

sub supers
{
   my $self = shift;
   return @{ $self->{supers} };
}

=head2 $methods = $class->methods

Return the methods as a HASH reference mapping names to
L<Tangence::Compiler::Method> instances.

=cut

sub methods
{
   my $self = shift;
   return $self->{methods};
}

=head2 $events = $class->events

Return the events as a HASH reference mapping names to
L<Tangence::Compiler::Event> instances.

=cut

sub events
{
   my $self = shift;
   return $self->{events};
}

=head2 $props = $class->props

Return the props as a HASH reference mapping names to
L<Tangence::Compiler::Property> instances.

=cut

sub props
{
   my $self = shift;
   return $self->{props};
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
