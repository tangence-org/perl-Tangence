package Tangence::Server::Connection;

use strict;

use base qw( Tangence::Stream );
use Tangence::Constants;

use Carp;

use Tangence::Server::Context;

sub new
{
   my $class = shift;
   my %args = @_;

   my $registry = delete $args{registry};

   my $self = $class->SUPER::new(
      %args,

      on_closed => sub {
         my ( $self ) = @_;

         foreach my $s ( @{ $self->{subscriptions} } ) {
            my ( $object, $event, $id ) = @$s;
            $object->unsubscribe_event( $event, $id );
         }
         foreach my $w ( @{ $self->{watches} } ) {
            my ( $object, $prop, $id ) = @$w;
            $object->unwatch_property( $prop, $id );
         }
      },
   );

   $self->{registry} = $registry;

   return $self;
}

sub identity
{
   my $self = shift;
   return $self->{identity};
}

sub get_by_id
{
   my $self = shift;
   my ( $id ) = @_;

   my $registry = $self->{registry};
   return $registry->get_by_id( $id );
}

sub handle_request_CALL
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $response = eval { $object->handle_request_CALL( $ctx, $message ) };
   $@ and return $ctx->responderr( $@ );

   $ctx->respond( $response );
}

sub handle_request_SUBSCRIBE
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();
   my $event = $message->unpack_str();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $id = $object->subscribe_event( $event,
      sub {
         my ( undef, $event, @args ) = @_;
         my $message = $object->generate_message_EVENT( $self, $event, @args );
         $self->request(
            request     => $message,
            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{subscriptions} }, [ $object, $event, $id ];

   $ctx->respond( Tangence::Message->new( $self, MSG_SUBSCRIBED ) );
}

sub handle_request_UNSUBSCRIBE
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();
   my $event = $message->unpack_str();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $edef = $object->can_event( $event ) or
      return $ctx->responderr( "Object cannot respond to event $event" );

   # Delete from subscriptions and obtain id
   my $id;
   @{ $self->{subscriptions} } = grep { $_->[0] == $object and $_->[1] eq $event and ( $id = $_->[2], 0 ) or 1 }
                                 @{ $self->{subscriptions} };
   defined $id or
      return $ctx->responderr( "Not subscribed to $event" );

   $object->unsubscribe_event( $event, $id );

   $ctx->respond( Tangence::Message->new( $self, MSG_OK ) );
}

sub handle_request_GETPROP
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $response = eval { $object->handle_request_GETPROP( $ctx, $message ) };
   $@ and return $ctx->responderr( $@ );

   $ctx->respond( $response );
}

sub handle_request_SETPROP
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $response = eval { $object->handle_request_SETPROP( $ctx, $message ) };
   $@ and return $ctx->responderr( $@ );

   $ctx->respond( $response );
}

sub handle_request_WATCH
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();
   my $prop  = $message->unpack_str();
   my $want_initial = $message->unpack_bool();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   $self->_install_watch( $object, $prop );

   $ctx->respond( Tangence::Message->new( $self, MSG_WATCHING ) );
   undef $ctx;

   return unless $want_initial;

   my $m = "get_prop_$prop";
   return unless( $object->can( $m ) );

   eval {
      my $value = $object->$m();
      my $message = $object->generate_message_UPDATE( $self, $prop, CHANGE_SET, $value );
      $self->request(
         request     => $message,
         on_response => sub { "IGNORE" },
      );
   }
   # ignore $@
}

sub handle_request_UNWATCH
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();
   my $prop  = $message->unpack_str();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   # Delete from watches and obtain id
   my $id;
   @{ $self->{watches} } = grep { $_->[0] == $object and $_->[1] eq $prop and ( $id = $_->[2], 0 ) or 1 }
                           @{ $self->{watches} };
   defined $id or
      return $ctx->responderr( "Not watching $prop" );

   $object->unwatch_property( $prop, $id );

   $ctx->respond( Tangence::Message->new( $self, MSG_OK ) );
}

sub handle_request_GETROOT
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $identity = $message->unpack_any();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};
   my $root = $registry->get_by_id( 1 );

   $self->{identity} = $identity;

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_obj( $root )
   );
}

sub handle_request_GETREGISTRY
{
   my $self = shift;
   my ( $token ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_obj( $registry )
   );
}

sub _install_watch
{
   my $self = shift;
   my ( $object, $prop ) = @_;

   my $id = $object->watch_property( $prop,
      sub {
         my ( undef, $prop, $how, @args ) = @_;
         my $message = $object->generate_message_UPDATE( $self, $prop, $how, @args );
         $self->request(
            request     => $message,
            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{watches} }, [ $object, $prop, $id ];
}

sub object_destroyed
{
   my $self = shift;
   my ( $obj ) = @_;

   if( my $subs = $self->{subscriptions} ) {
      my $i = 0;
      while( $i < @$subs ) {
         my $s = $subs->[$i];

         $i++, next unless $s->[0] == $obj;

         my ( undef, $event, $id ) = @$s;
         $obj->unsubscribe_event( $event, $id );

         splice @$subs, $i, 1;
         # No $i++
      }
   }

   if( my $watches = $self->{watches} ) {
      my $i = 0;
      while( $i < @$watches ) {
         my $w = $watches->[$i];

         $i++, next unless $w->[0] == $obj;

         my ( undef, $prop, $id ) = @$w;
         $obj->unwatch_property( $prop, $id );

         splice @$watches, $i, 1;
         # No $i++
      }
   }

   $self->SUPER::object_destroyed( @_ );
}

1;
