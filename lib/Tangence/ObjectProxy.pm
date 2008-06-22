package Tangence::ObjectProxy;

use strict;

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

   my $conn = $self->{conn};
   $conn->call(
      objid => $self->{id},
      %args
   );
}

sub subscribe
{
   my $self = shift;
   my ( $event, $callback ) = @_;

   my $conn = $self->{conn};
   $conn->subscribe( $self->{id}, $event, $callback );
}

sub watch
{
   my $self = shift;
   my ( $prop, $callback, $want_initial ) = @_;

   my $conn = $self->{conn};
   $conn->watch( $self->{id}, $prop, $callback, $want_initial );
}

1;
