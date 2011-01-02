#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Registry;

use strict;
use warnings;
use base qw( Tangence::Object );

our $VERSION = '0.02';

use Carp;

use Tangence::Constants;

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

sub new
{
   my $class = shift;

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

   return $self;
}

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

sub construct
{
   my $self = shift;
   my ( $type, @args ) = @_;

   my $id = shift @{ $self->{freeids} } || ( $self->{nextid}++ );

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

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
