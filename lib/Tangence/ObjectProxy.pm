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

sub call_method
{
   my $self = shift;
   my %args = @_;

   my $method = delete $args{method} or croak "Need a method";
   my $args   = delete $args{args};

   ref( my $on_result = delete $args{on_result} ) eq "CODE" 
      or croak "Expected 'on_result' as a CODE ref";
   ref( my $on_error = delete $args{on_error} ) eq "CODE" 
      or croak "Expected 'on_error' as a CODE ref";

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_CALL, [ $self->id, $method, @$args ] ],

      on_response => sub {
         my ( $code, $data ) = @{$_[0]};
         if( $code == MSG_RESULT ) {
            $on_result->( $data );
         }
         elsif( $code == MSG_ERROR ) {
            $on_error->( $data );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      },
   );
}

sub subscribe_event
{
   my $self = shift;
   my %args = @_;

   my $event = delete $args{event} or croak "Need a event";
   ref( my $callback = delete $args{on_fire} ) eq "CODE"
      or croak "Expected 'on_fire' as a CODE ref";

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

sub set_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   # value can quite legitimately be undef
   exists $args{value} or croak "Need a value";
   my $value = delete $args{value};

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_SETPROP, [ $self->id, $property, $value ] ],
      %args
   );
}

sub watch_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";
   ref( my $callback = delete $args{on_change} ) eq "CODE"
      or croak "Expected 'on_change' as a CODE ref";

   my $conn = $self->{conn};
   $conn->watch( $self->{id}, $property, $callback, $args{want_initial} );
}

1;
