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
   
   my $objid  = $message->unpack_int();
   my $method = $message->unpack_str();
   my @args   = $message->unpack_all_data();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $mdef = $object->can_method( $method ) or
      return $ctx->responderr( "Object cannot respond to method $method" );

   my $m = "method_$method";

   $object->can( $m ) or
      return $ctx->responderr( "Object cannot run method $method" );

   my $result = eval { $object->$m( $ctx, @args ) };

   $@ and return $ctx->responderr( $@ );

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_any( $result )
   );
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

   my $edef = $object->can_event( $event ) or
      return $ctx->responderr( "Object cannot respond to event $event" );

   my $id = $object->subscribe_event( $event,
      sub {
         my ( undef, $event, @args ) = @_;
         $self->request(
            request => Tangence::Message->new( $self, MSG_EVENT )
               ->pack_int( $objid )
               ->pack_str( $event )
               ->pack_all_data( @args ),

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
   my $id    = $message->unpack_int();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $edef = $object->can_event( $event ) or
      return $ctx->responderr( "Object cannot respond to event $event" );

   $object->unsubscribe_event( $event, $id );

   @{ $self->{subscriptions} } = grep { $_->[2] eq $id } @{ $self->{subscriptions} };

   $ctx->respond( Tangence::Message->new( $self, MSG_OK ) );
}

sub handle_request_GETPROP
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

   my $m = "get_prop_$prop";

   $object->can( $m ) or
      return $ctx->responderr( "Object cannot get property $prop" );

   my $result = eval { $object->$m() };

   $@ and return $ctx->responderr( $@ );

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_any( $result )
   );
}

sub handle_request_SETPROP
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $objid = $message->unpack_int();
   my $prop  = $message->unpack_str();
   my $value = $message->unpack_any();

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

   $ctx->respond( Tangence::Message->new( $self, MSG_OK ) );
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
      my $result = $object->$m();

      $self->request(
         request => Tangence::Message->new( $self, MSG_UPDATE )
            ->pack_int( $objid )
            ->pack_str( $prop )
            ->pack_typed( "u8", CHANGE_SET )
            ->pack_any( $result ),

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
   my $id    = $message->unpack_int();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $pdef = $object->can_property( $prop ) or
      return $ctx->responderr( "Object does not have property $prop" );

   $object->unwatch_property( $prop, $id );

   @{ $self->{watches} } = grep { $_->[2] eq $id } @{ $self->{watches} };

   $ctx->respond( Tangence::Message->new( $self, MSG_OK ) );
}

sub handle_request_GETROOT
{
   my $self = shift;
   my ( $token, $message ) = @_;
   
   my $identity = $message->unpack_any();

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   $self->{identity} = $identity;

   my $result = $registry->get_by_id( 1 );
   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_any( $result )
   );
}

sub handle_request_GETREGISTRY
{
   my $self = shift;
   my ( $token ) = @_;

   my $ctx = Tangence::Server::Context->new( $self, $token );

   my $registry = $self->{registry};

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_any( $registry )
   );
}

sub _install_watch
{
   my $self = shift;
   my ( $object, $prop ) = @_;

   my $id = $object->watch_property( $prop,
      sub {
         my ( undef, $prop, $how, @value ) = @_;
         $self->request(
            request => Tangence::Message->new( $self, MSG_UPDATE )
               ->pack_int( $object->id )
               ->pack_str( $prop )
               ->pack_typed( "u8", $how )
               ->pack_all_data( @value ),

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
