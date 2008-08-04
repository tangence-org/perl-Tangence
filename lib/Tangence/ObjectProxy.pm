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
   $conn->subscribe( 
      objid    => $self->{id},
      event    => $event,
      callback => sub { foreach my $cb ( @cbs ) { $cb->( @_ ) } },
      on_subscribed => $args{on_subscribed},
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

sub _update_property
{
   my $self = shift;
   my ( $property, $how, @value ) = @_;

   my $prop = $self->{props}->{$property} ||= {};

   my $dim = $prop->{dim};

   if( $dim == DIM_SCALAR ) {
      $self->_update_property_scalar( $prop->{cache}, $how, @value );
   }
   elsif( $dim == DIM_HASH ) {
      $self->_update_property_hash( $prop->{cache}, $how, @value );
   }
   elsif( $dim == DIM_ARRAY ) {
      $self->_update_property_array( $prop->{cache}, $how, @value );
   }
   elsif( $dim == DIM_OBJSET ) {
      $self->_update_property_objset( $prop->{cache}, $how, @value );
   }
   else {
      croak "Unrecognised property dimension $dim for $property";
   }
}

sub _update_property_scalar
{
   my $self = shift;
   my ( $cache, $how, @value ) = @_;

   if( $how == CHANGE_SET ) {
      $_[0] = $value[0];
   }
   else {
      croak "Change type $how is not valid for a scalar property";
   }
}

sub _update_property_hash
{
   my $self = shift;
   my ( $cache, $how, @value ) = @_;

   if( $how == CHANGE_SET ) {
      $_[0] = { %{ $value[0] } };
   }
   elsif( $how == CHANGE_ADD ) {
      $cache->{$value[0]} = $value[1];
   }
   elsif( $how == CHANGE_DEL ) {
      delete $cache->{$value[0]};
   }
   else {
      croak "Change type $how is not valid for a hash property";
   }
}

sub _update_property_array
{
   my $self = shift;
   my ( $cache, $how, @value ) = @_;

   if( $how == CHANGE_SET ) {
      $_[0] = [ @{ $value[0] } ];
   }
   elsif( $how == CHANGE_PUSH ) {
      push @$cache, @value;
   }
   elsif( $how == CHANGE_SHIFT ) {
      splice @$cache, 0, $value[0], ();
   }
   elsif( $how == CHANGE_SPLICE ) {
      my ( $start, $count, @new ) = @value;
      splice @$cache, $start, $count, @new;
   }
   else {
      croak "Change type $how is not valid for an array property";
   }
}

sub get_property_cached
{
   my $self = shift;
   my ( $property ) = @_;

   if( exists $self->{props}->{$property}->{cache} ) {
      return $self->{props}->{$property}->{cache};
   }

   croak "$self does not have a cached property '$property'";
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

   if( my $cbs = $self->{props}->{$property}->{cbs} ) {
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
   $self->{props}->{$property}->{cbs} = \@cbs;

   my $conn = $self->{conn};
   $conn->watch(
      objid    => $self->{id},
      property => $property, 
      callback => sub {
         my ( undef, undef, $how, @value ) = @_;
         $self->_update_property( $property, $how, @value );
         foreach my $cb ( @cbs ) { $cb->( @_ ) }
      },

      on_watched => sub {
         $self->{props}->{$property}->{dim} = $_[0];
         $args{on_watched}->() if $args{on_watched};
      },

      want_initial => $want_initial,
   );
}

1;
