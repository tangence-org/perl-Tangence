#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Registry;

use strict;
use warnings;
use base qw( Tangence::Object );

our $VERSION = '0.05';

use Carp;

use Tangence::Constants;

use Tangence::Compiler::Parser;

use Scalar::Util qw( weaken );

Tangence::Meta::Class->renew(
   __PACKAGE__,

   methods => {
      get_by_id => {
         args => [qw( int )],
         ret  => 'obj',
      },
   },

   events => {
      object_constructed => {
         args => [qw( int )],
      },
      object_destroyed => {
         args => [qw( int )],
      },
   },

   props => {
      objects => {
         dim  => DIM_HASH,
         type => 'str',
      }
   },
);

=head1 NAME

C<Tangence::Registry> - object manager for a C<Tangence> server

=head1 DESCRIPTION

This subclass of L<Tangence::Object> acts as a container for all the exposed
objects in a L<Tangence> server. The registry is used to create exposed
objects, and manages their lifetime. It maintains a reference to all the
objects it creates, so it can dispatch incoming messages from clients to them.

=cut

=head1 CONSTRUCTOR

=cut

=head2 $registry = Tangence::Registry->new

Returns a new instance of a C<Tangence::Registry> object. An entire server
requires one registry object; it will be shared among all the client
connections to that server.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $id = 0;

   my $self = $class->SUPER::new(
      id => $id,
      registry => "BOOTSTRAP",
      meta => Tangence::Meta::Class->new( $class ),
   );
   weaken( $self->{registry} = $self );
   
   $self->{objects} = { $id => $self };
   weaken( $self->{objects}{$id} );
   $self->add_prop_objects( $id => $self->describe );

   $self->{nextid}  = 1;
   $self->{freeids} = []; # free'd ids we can reuse

   if( my $tanfile = $args{tanfile} ) {
      my $parsed = Tangence::Compiler::Parser->new->from_file( $tanfile );

      $self->{classes} = { map {
         my $class = $_;
         $class =~ s{\.}{::}g;

         $class => Tangence::Meta::Class->new( $class, %{ $parsed->{$_} } )
      } keys %$parsed };
   }
   else {
      croak "Expected 'tanfile'";
   }

   return $self;
}

=head1 METHODS

=cut

=head2 $obj = $registry->get_by_id( $id )

Returns the object with the given object ID.

This method is exposed to clients.

=cut

sub get_by_id
{
   my $self = shift;
   my ( $id ) = @_;

   return $self->{objects}->{$id};
}

sub method_get_by_id
{
   my $self = shift;
   my ( $ctx, $id ) = @_;
   return $self->get_by_id( $id );
}

=head2 $obj = $registry->construct( $type, @args )

Constructs a new exposed object of the given type, and returns it. Any
additional arguments are passed to the object's constructor.

=cut

sub construct
{
   my $self = shift;
   my ( $type, @args ) = @_;

   my $id = shift @{ $self->{freeids} } || ( $self->{nextid}++ );

   exists $self->{classes}{$type} or croak "Registry cannot construct a '$type' as no class definition exists";

   eval { $type->can( "new" ) } or croak "Registry cannot construct a '$type' as it has no ->new() method";

   my $obj = $type->new(
      registry => $self,
      id       => $id,
      @args
   );

   $self->fire_event( "object_constructed", $id );

   weaken( $self->{objects}->{$id} = $obj );
   $self->add_prop_objects( $id => $obj->describe );

   return $obj;
}

sub destroy_object
{
   my $self = shift;
   my ( $obj ) = @_;

   my $id = $obj->id;

   exists $self->{objects}->{$id} or croak "Cannot destroy ID $id - does not exist";

   $self->del_prop_objects( $id );

   $self->fire_event( "object_destroyed", $id );

   push @{ $self->{freeids} }, $id; # Recycle the ID
}

sub get_meta_class
{
   my $self = shift;
   my ( $class ) = @_;

   return Tangence::Meta::Class->new( $class );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
