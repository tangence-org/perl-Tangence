#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Compiler::Event;

use strict;
use warnings;

our $VERSION = '0.07';

use Scalar::Util qw( weaken );

=head1 NAME

C<Tangence::Compiler::Event> - structure representing one C<Tangence> event

=head1 DESCRIPTION

This data structure object stores information about one L<Tangence> class
event, as parsed by L<Tangence::Compiler::Parser>. Once constructed, such
objects are immutable.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $event = Tangence::Compiler::Event->new( %args )

Returns a new instance initialised by the given arguments.

=over 8

=item class => Tangence::Compiler::Class

Reference to the containing class

=item name => STRING

Name of the event

=item argtypes => ARRAY

Optional ARRAY reference containing arguments as
L<Tangence::Compiler::Argument> references.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   $args{arguments} ||= [];
   my $self = bless \%args, $class;
   weaken $self->{class};
   return $self;
}

=head1 ACCESSORS

=cut

=head2 $class = $event->class

Returns the class the event is a member of

=cut

sub class
{
   my $self = shift;
   return $self->{class};
}

=head2 $name = $event->name

Returns the name of the class

=cut

sub name
{
   my $self = shift;
   return $self->{name};
}

=head2 @arguments = $event->arguments

Return the arguments in a list of L<Tangence::Compiler::Argument> references.

=cut

sub arguments
{
   my $self = shift;
   return @{ $self->{arguments} };
}

=head2 @argtypes = $event->argtypes

Return the argument types in a list of strings.

=cut

sub argtypes
{
   my $self = shift;
   return map { $_->type } $self->arguments;
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

