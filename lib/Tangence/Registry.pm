package Tangence::Registry;

use strict;
use base qw( Tangence::Object );

use Carp;

use Tangence::Constants;

use Scalar::Util qw( weaken );

our %METHODS = (
   get_by_id => {
      args => [qw( int )],
      ret  => 'obj',
   },
);

our %EVENTS = (
   object_constructed => {
      args => [qw( int )],
   },
   object_destroyed => {
      args => [qw( int )],
   },
);

our %PROPS = (
   objects => {
      dim  => DIM_HASH,
      type => 'str',
   }
);

sub new
{
   my $class = shift;

   my $id = 0;

   my $self = $class->SUPER::new(
      id => $id,
      registry => "BOOTSTRAP",
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

1;
