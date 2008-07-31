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

      on_error => $args{on_error},
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

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_CALL, $self->id, $method, @$args ],

      on_response => sub {
         my ( $code, @data ) = @{$_[0]};
         if( $code == MSG_RESULT ) {
            $on_result->( @data );
         }
         elsif( $code == MSG_ERROR ) {
            $on_error->( @data );
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

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      push @$cbs, $callback;
      return;
   }

   my @cbs = ( $callback );
   $self->{subscriptions}->{$event} = \@cbs;

   my $conn = $self->{conn};
   $conn->subscribe( $self->{id}, $event,
                     sub { foreach my $cb ( @cbs ) { $cb->( @_ ) } }
                   );
}

sub get_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   ref( my $on_value = delete $args{on_value} ) eq "CODE" 
      or croak "Expected 'on_value' as a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_GETPROP, $self->id, $property ],

      on_response => sub {
         my ( $code, @data ) = @{$_[0]};
         if( $code == MSG_RESULT ) {
            $on_value->( @data );
         }
         elsif( $code == MSG_ERROR ) {
            $on_error->( @data );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      },
   );
}

sub set_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   my $on_done = delete $args{on_done};
   !defined $on_done or ref $on_done eq "CODE"
      or croak "Expected 'on_done' to be a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   # value can quite legitimately be undef
   exists $args{value} or croak "Need a value";
   my $value = delete $args{value};

   my $conn = $self->{conn};
   $conn->request(
      request => [ MSG_SETPROP, $self->id, $property, $value ],

      on_response => sub {
         my ( $code, @data ) = @{$_[0]};
         if( $code == MSG_OK ) {
            $on_done->() if $on_done;
         }
         elsif( $code == MSG_ERROR ) {
            $on_error->( @data );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      },
   );
}

sub watch_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";
   ref( my $callback = delete $args{on_change} ) eq "CODE"
      or croak "Expected 'on_change' as a CODE ref";
   my $want_initial = delete $args{want_initial};

   if( my $cbs = $self->{watches}->{$property} ) {
      if( $want_initial ) {
         $self->get_property(
            property => $property,
            on_value => sub {
               $callback->( $self->{id}, $property, CHANGE_SET, $_[0] );
               push @$cbs, $callback;
            },
         );
      }
      else {
         push @$cbs, $callback;
      }

      return;
   }

   my @cbs = ( $callback );
   $self->{watches}->{$property} = \@cbs;

   my $conn = $self->{conn};
   $conn->watch( $self->{id}, $property, 
                 sub { foreach my $cb ( @cbs ) { $cb->( @_ ) } },
                 $want_initial
               );
}

1;
