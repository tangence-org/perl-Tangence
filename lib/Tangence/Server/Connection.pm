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
   my ( $token, $objid, $method, @args ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $mdef = $object->can_method( $method ) or
      return $ctx->responderr( "Object cannot respond to method $method" );

   my $result = eval { $object->$method( @args ) };

   $@ and return $ctx->responderr( $@ );

   $ctx->respond( MSG_RESULT, $result );
}

sub handle_request_SUBSCRIBE
{
   my $self = shift;
   my ( $token, $objid, $event ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $edef = $object->can_event( $event ) or
      return $ctx->responderr( "Object cannot respond to event $event" );

   my $id = $object->subscribe_event( $event,
      sub {
         my ( undef, $event, @args ) = @_;
         $self->request(
            request => [ MSG_EVENT, $objid, $event, @args ],

            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{subscriptions} }, [ $object, $event, $id ];

   $ctx->respond( MSG_SUBSCRIBED );
}

sub handle_request_UNSUBSCRIBE
{
   my $self = shift;
   my ( $token, $objid, $event, $id ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $edef = $object->can_event( $event ) or
      return $ctx->responderr( "Object cannot respond to event $event" );

   $object->unsubscribe_event( $event, $id );

   @{ $self->{subscriptions} } = grep { $_->[2] eq $id } @{ $self->{subscriptions} };

   $ctx->respond( MSG_OK );
}

sub handle_request_GETPROP
{
   my $self = shift;
   my ( $token, $objid, $prop ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   my $m = "get_prop_$prop";

   $object->can( $m ) or
      return $ctx->responderr( "Object cannot get property $prop" );

   my $result = eval { $object->$m() };

   $@ and return $ctx->responderr( $@ );

   $ctx->respond( MSG_RESULT, $result );
}

sub handle_request_SETPROP
{
   my $self = shift;
   my ( $token, $objid, $prop, $value ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   my $m = "set_prop_$prop";

   $object->can( $m ) or
      return $ctx->responderr( "Object cannot set property $prop" );

   eval { $object->$m( $value ) };

   $@ and return $ctx->responderr( $@ );

   $ctx->respond( MSG_OK );
}

sub handle_request_WATCH
{
   my $self = shift;
   my ( $token, $objid, $prop, $want_initial ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   $self->_install_watch( $object, $prop );

   $ctx->respond( MSG_WATCHING );
   undef $ctx;

   return unless $want_initial;

   my $m = "get_prop_$prop";
   return unless( $object->can( $m ) );

   eval {
      my $result = $object->$m();

      $self->request(
         request => [ MSG_UPDATE, $objid, $prop, CHANGE_SET, $result ],

         on_response => sub { "IGNORE" },
      );
   }
   # ignore $@
}

sub handle_request_UNWATCH
{
   my $self = shift;
   my ( $token, $objid, $prop, $id ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   $object->unwatch_property( $prop, $id );

   @{ $self->{watches} } = grep { $_->[2] eq $id } @{ $self->{watches} };

   $ctx->respond( MSG_OK );
}

sub handle_request_GETROOT
{
   my $self = shift;
   my ( $token, $identity ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   $self->{identity} = $identity;

   $ctx->respond( MSG_RESULT, $registry->get_by_id( 1 ) );
}

sub handle_request_GETREGISTRY
{
   my $self = shift;
   my ( $token, $identity ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   $ctx->respond( MSG_RESULT, $registry );
}

sub _install_watch
{
   my $self = shift;
   my ( $object, $prop ) = @_;

   my $id = $object->watch_property( $prop,
      sub {
         my ( undef, $prop, $how, @value ) = @_;
         $self->request(
            request => [ MSG_UPDATE, $object->id, $prop, $how, @value ],

            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{watches} }, [ $object, $prop, $id ];
}

1;
