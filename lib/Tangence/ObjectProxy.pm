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

      class  => $args{class},
      schema => $args{schema},

      on_error => $args{on_error},
   }, $class;

   return $self;
}

sub destroy
{
   my $self = shift;

   $self->{destroyed} = 1;

   foreach my $cb ( @{ $self->{subscriptions}->{destroy} } ) {
      $cb->( $self, "destroy" );
   }

   undef %$self;
   $self->{destroyed} = 1;
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

sub class
{
   my $self = shift;
   return $self->{class};
}

sub introspect
{
   my $self = shift;
   if( !@_ ) {
      return $self->{schema};
   }
   else {
      my $section = shift;
      return $self->{schema}->{$section};
   }
}

sub can_method
{
   my $self = shift;
   my ( $method ) = @_;
   return $self->{schema}->{methods}->{$method};
}

sub can_event
{
   my $self = shift;
   my ( $event ) = @_;
   return $self->{schema}->{events}->{$event};
}

sub can_property
{
   my $self = shift;
   my ( $property ) = @_;
   return $self->{schema}->{properties}->{$property};
}

# Don't want to call it "isa"
sub proxy_isa 
{
   my $self = shift;
   if( @_ ) {
      my ( $class ) = @_;
      return !! grep { $_ eq $class } @{ $self->{schema}->{isa} };
   }
   else {
      return @{ $self->{schema}->{isa} };
   }
}

sub grab
{
   my $self = shift;
   my ( $smashdata ) = @_;

   foreach my $property ( keys %{ $smashdata } ) {
      my $value = $smashdata->{$property};
      my $dim = $self->{schema}->{properties}->{$property}->{dim};

      if( $dim == DIM_OBJSET ) {
         # Comes across in a LIST. We need to map id => obj
         $value = { map { $_->id => $_ } @$value };
      }

      my $prop = $self->{props}->{$property} ||= {};
      $prop->{cache} = $value;
   }
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

   my $mdef = $self->can_method( $method );
   croak "Class ".$self->class." does not have a method $method" unless $mdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_CALL )
         ->pack_int( $self->id )
         ->pack_str( $method )
         ->pack_all_data( $args ? @$args : () ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            my $result = $message->unpack_any();
            $on_result->( $result );
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
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

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $on_subscribed = $args{on_subscribed};

   my $edef = $self->can_event( $event );
   croak "Class ".$self->class." does not have an event $event" unless $edef;

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      push @$cbs, $callback;
      return;
   }

   my @cbs = ( $callback );
   $self->{subscriptions}->{$event} = \@cbs;

   return if $event eq "destroy"; # This is automatically handled

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_SUBSCRIBE )
         ->pack_int( $self->id )
         ->pack_str( $event ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_SUBSCRIBED ) {
            $on_subscribed->() if $on_subscribed;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $message ) = @_;

   my $event = $message->unpack_str();
   my @args  = $message->unpack_all_data();

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      foreach my $cb ( @$cbs ) { $cb->( $self, $event, @args ) }
   }
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

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_GETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            my @data = $message->unpack_all_data();
            $on_value->( @data );
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

sub _update_property
{
   my $self = shift;
   my ( $property, $how, @value ) = @_;

   my $prop = $self->{props}->{$property} ||= {};

   my $dim = $self->{schema}->{properties}->{$property}->{dim};

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

   if( my $cbs = $self->{props}->{$property}->{cbs} ) {
      foreach my $cb ( @$cbs ) { $cb->( $self, $property, $how, @value ) }
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

sub _update_property_objset
{
   my $self = shift;
   my ( $cache, $how, @value ) = @_;

   if( $how == CHANGE_SET ) {
      # Comes across in a LIST. We need to map id => obj
      $_[0] = { map { $_->id => $_ } @{ $value[0] } };
   }
   elsif( $how == CHANGE_ADD ) {
      # Comes as object only
      my $obj = $value[0];
      $cache->{$obj->id} = $obj;
   }
   elsif( $how == CHANGE_DEL ) {
      # Comes as ID number only
      delete $cache->{$value[0]};
   }
   else {
      croak "Change type $how is not valid for an objset property";
   }
}

sub prop
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

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_SETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_any( $value ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_OK ) {
            $on_done->() if $on_done;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
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

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $want_initial = delete $args{want_initial};

   my $on_watched = $args{on_watched};

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   # Smashed properties behave differently
   my $smash = $pdef->{smash};

   if( my $cbs = $self->{props}->{$property}->{cbs} ) {
      if( $want_initial and !$smash ) {
         $self->get_property(
            property => $property,
            on_value => sub {
               $callback->( $self, $property, CHANGE_SET, $_[0] );
               push @$cbs, $callback;
            },
         );
      }
      elsif( $want_initial and $smash ) {
         $callback->( $self, $property, CHANGE_SET, $self->{props}->{$property}->{cache} );
         push @$cbs, $callback;
      }
      else {
         push @$cbs, $callback;
      }

      return;
   }

   $self->{props}->{$property}->{cbs} = [ $callback ];

   if( $smash ) {
      if( $want_initial ) {
         $callback->( $self, $property, CHANGE_SET, $self->{props}->{$property}->{cache} );
      }
      $on_watched->() if $on_watched;
      return;
   }

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_WATCH )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_bool( $want_initial ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_WATCHING ) {
            $on_watched->() if $on_watched;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

sub handle_request_UPDATE
{
   my $self = shift;
   my ( $message ) = @_;

   my $prop  = $message->unpack_str();
   my $how   = $message->unpack_typed( "u8" );
   my @value = $message->unpack_all_data();

   $self->_update_property( $prop, $how, @value );
}

1;
