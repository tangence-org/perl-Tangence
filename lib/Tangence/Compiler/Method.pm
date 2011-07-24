#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Compiler::Method;

use strict;
use warnings;

our $VERSION = '0.07';

=head1 NAME

C<Tangence::Compiler::Method> - structure representing one C<Tangence> method

=head1 DESCRIPTION

This data structure object stores information about one L<Tangence> class
method, as parsed by L<Tangence::Compiler::Parser>. Once constructed, such
objects are immutable.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $method = Tangence::Compiler::Method->new( %args )

Returns a new instance initialised by the given arguments.

=over 8

=item name => STRING

Name of the method

=item args => ARRAY

Optional ARRAY reference containing arguments as
L<Tangence::Compiler::Argument> references.

=item ret => STRING

Optional string giving the return value type as a string.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;
   $args{arguments} ||= [];
   bless \%args, $class;
}

=head1 ACCESSORS

=cut

=head2 $name = $method->name

Returns the name of the class

=cut

sub name
{
   my $self = shift;
   return $self->{name};
}

=head2 @arguments = $method->arguments

Return the arguments in a list of L<Tangence::Compiler::Argument> references.

=cut

sub arguments
{
   my $self = shift;
   return @{ $self->{arguments} };
}

=head2 @argtypes = $method->argtypes

Return the argument types in a list of strings.

=cut

sub argtypes
{
   my $self = shift;
   return map { $_->type } $self->arguments;
}

=head2 $ret = $method->ret

Returns the return type as a string, or C<undef> if the method does not return
a value.

=cut

sub ret
{
   my $self = shift;
   return $self->{ret};
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

