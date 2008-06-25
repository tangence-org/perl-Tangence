package Tangence::ObjectProxy;

use strict;
use Carp;

use Tangence::Constants;

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = bless {
      conn => $args{conn},
      id   => $args{id},
   }, $class;

   return $self;
}

use overload '""' => \&STRING;

sub STRING
{
   my $self = shift;
   return "Tangence::ObjectProxy[id=$self->{id}]";
}

sub id
{
   my $self = shift;
   return $self->{id};
}

sub call
{
   my $self = shift;
   my %args = @_;

   my $method = delete $args{method} or croak "Need a method";
   my $args   = delete $args{args};

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_CALL, [ $self->id, $method, @$args ] ],
      %args,
   );
}

sub subscribe
{
   my $self = shift;
   my ( $event, $callback ) = @_;

   my $conn = $self->{conn};
   $conn->subscribe( $self->{id}, $event, $callback );
}

sub get_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_GETPROP, [ $self->id, $property ] ],
      %args
   );
}

sub watch
{
   my $self = shift;
   my ( $prop, $callback, $want_initial ) = @_;

   my $conn = $self->{conn};
   $conn->watch( $self->{id}, $prop, $callback, $want_initial );
}

1;
