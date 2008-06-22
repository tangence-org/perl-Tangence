package Tangence::Registry;

use strict;
use base qw( Tangence::Object );

use Carp;

use Tangence::Constants;

our %METHODS = (
);

our %EVENTS = (
   object_constructed => {
      args => 'I',
   },
   object_destroyed => {
      args => 'I',
   },
);

our %PROPS = (
   objects => {
      dim  => DIM_HASH,
      type => 's',
   }
);

sub new
{
   my $class = shift;

   my $id = 0;

   my $self = $class->SUPER::new(
      id => $id,
   );
   
   $self->{objects} = {
      $id => $self, # registry is object 0
   };

   $self->{nextid}  = 1;
   $self->{freeids} = []; # free'd ids we can reuse

   return $self;
}

sub get_prop_objects
{
   my $self = shift;

   my $objects = $self->{objects};

   return { map { $_ => $objects->{$_}->describe } keys %$objects };
}

sub get_by_id
{
   my $self = shift;
   my ( $id ) = @_;

   return $self->{objects}->{$id};
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

   $self->{objects}->{$id} = $obj;
   $self->update_property( "objects", CHANGE_ADD, $id, $obj->describe );

   return $obj;
}

sub destroy_object
{
   my $self = shift;
   my ( $obj ) = @_;

   $self->destroy_id( $obj->id );
}

sub destroy_id
{
   my $self = shift;
   my ( $id ) = @_;

   exists $self->{objects}->{$id} or croak "Cannot destroy ID $id - does not exist";

   my $obj = delete $self->{objects}->{$id};
   $self->update_property( "objects", CHANGE_DEL, $id );

   $obj->destroy;

   $self->fire_event( "object_destroyed", $id );

   push @{ $self->{freeids} }, $id; # Recycle the ID
}

1;
