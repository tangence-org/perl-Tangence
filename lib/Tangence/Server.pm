package Tangence::Server;

use strict;

use Carp;

sub new
{
   my $class = shift;
   my %args = @_;

   my $loop     = delete $args{loop} or croak "Need a 'loop'";
   my $registry = delete $args{registry} or croak "Need a 'registry'";

   my $self = bless {
      loop     => $loop,
      registry => $registry,
   }, $class;

   return $self;
}

sub listen
{
   my $self = shift;
   my %listenargs = @_;

   my $loop = $self->{loop};

   $loop->listen(
      %listenargs,

      on_accept => sub { $self->new_be( handle => $_[0] ) },
   );
}

sub new_be
{
   my $self = shift;
   my %args = @_;

   my $be = Tangence::Server::Connection->new( %args,
      registry => $self->{registry},
   );

   $self->{loop}->add( $be );
}

1;

package Tangence::Server::Connection;

use strict;

use base qw( Tangence::Stream );
use Tangence::Constants;

use Carp;

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
   my ( $token, $request ) = @_;

   my ( $objid, $method, @args ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $mdef = $object->can_method( $method );

   unless( $mdef ) {
      $self->respond( $token, [ MSG_ERROR, "Object cannot respond to method $method" ] );
      return;
   }

   unshift @args, $self, $token if $mdef->{async};

   eval {
      my $result = $object->$method( @args );

      $self->respond( $token, [ MSG_RESULT, $result ] );
   };
   if( $@ ) {
      $self->respond( $token, [ MSG_ERROR, $@ ] );
   }
}

sub handle_request_SUBSCRIBE
{
   my $self = shift;
   my ( $token, $request ) = @_;

   my ( $objid, $event ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $edef = $object->can_event( $event );

   unless( $edef ) {
      $self->respond( $token, [ MSG_ERROR, "Object cannot respond to event $event" ] );
      return;
   }

   my $id = $object->subscribe_event( $event,
      sub {
         my ( undef, @args ) = @_;
         $self->request(
            request => [ MSG_EVENT, [ $objid, $event, @args ] ],

            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{subscriptions} }, [ $object, $event, $id ];

   $self->respond( $token, [ MSG_SUBSCRIBED, $id ] );
}

sub handle_request_UNSUBSCRIBE
{
   my $self = shift;
   my ( $token, $request ) = @_;

   my ( $objid, $event, $id ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $edef = $object->can_event( $event );

   unless( $edef ) {
      $self->respond( $token, [ MSG_ERROR, "Object cannot respond to event $event" ] );
      return;
   }

   $object->unsubscribe_event( $event, $id );

   @{ $self->{subscriptions} } = grep { $_->[2] eq $id } @{ $self->{subscriptions} };

   $self->respond( $token, [ MSG_OK ] );
}

sub handle_request_GETPROP
{
   my $self = shift;
   my ( $token, $request ) = @_;

   my ( $objid, $prop ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $pdef = $object->can_property( $prop );

   unless( $pdef ) {
      $self->respond( $token, [ MSG_ERROR, "Object does not have property $prop" ] );
      return;
   }

   my $m = "get_prop_$prop";
   unless( $object->can( $m ) ) {
      $self->respond( $token, [ MSG_ERROR, "Object cannot get property $prop" ] );
      return;
   }

   eval {
      my $result = $object->$m();

      $self->respond( $token, [ MSG_RESULT, $result ] );
   };
   if( $@ ) {
      $self->respond( $token, [ MSG_ERROR, $@ ] );
   }
}

sub handle_request_WATCH
{
   my $self = shift;
   my ( $token, $request ) = @_;

   my ( $objid, $prop, $want_initial ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $pdef = $object->can_property( $prop );

   unless( $pdef ) {
      $self->respond( $token, [ MSG_ERROR, "Object does not have property $prop" ] );
      return;
   }

   my $id = $object->watch_property( $prop,
      sub {
         my ( undef, $prop, $how, @value ) = @_;
         $self->request(
            request => [ MSG_UPDATE, [ $objid, $prop, $how, @value ] ],

            on_response => sub { "IGNORE" },
         );
      }
   );

   push @{ $self->{watches} }, [ $object, $prop, $id ];

   $self->respond( $token, [ MSG_WATCHING, $id ] );

   return unless $want_initial;

   my $m = "get_prop_$prop";
   return unless( $object->can( $m ) );

   eval {
      my $result = $object->$m();

      $self->request(
         request => [ MSG_UPDATE, [ $objid, $prop, CHANGE_SET, $result ] ],

         on_response => sub { "IGNORE" },
      );
   }
   # ignore $@
}

sub handle_request_UNWATCH
{
   my $self = shift;
   my ( $token, $request ) = @_;

   my ( $objid, $prop, $id ) = @$request;

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid );
   unless( defined $object ) {
      $self->respond( $token, [ MSG_ERROR, "No such object with id $objid" ] );
      return;
   }

   my $pdef = $object->can_property( $prop );

   unless( $pdef ) {
      $self->respond( $token, [ MSG_ERROR, "Object does not have property $prop" ] );
      return;
   }

   $object->unwatch_property( $prop, $id );

   @{ $self->{watches} } = grep { $_->[2] eq $id } @{ $self->{watches} };

   $self->respond( $token, [ MSG_OK ] );
}

1;