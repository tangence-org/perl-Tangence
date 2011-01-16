#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Net::Async::Tangence::ServerProtocol;

use strict;
use warnings;

use base qw( Net::Async::Tangence::Protocol );

our $VERSION = '0.02';

use Carp;

use Tangence::Constants;

use Net::Async::Tangence::ServerContext;

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->{registry} = delete $params->{registry};

   $params->{on_closed} ||= undef;
}

sub configure
{
   my $self = shift;
   my %params = @_;

   if( exists $params{on_closed} ) {
      my $on_closed = $params{on_closed};
      $params{on_closed} = sub {
         my $self = shift;

         $on_closed->( $self ) if $on_closed;

         $self->shutdown;
      };
   }

   $self->SUPER::configure( %params );
}

sub shutdown
{
   my $self = shift;

   if( my $subscriptions = $self->{subscriptions} ) {
      foreach my $s ( @$subscriptions ) {
         my ( $object, $event, $id ) = @$s;
         $object->unsubscribe_event( $event, $id );
      }

      undef @$subscriptions;
   }

   if( my $watches = $self->{watches} ) {
      foreach my $w ( @$watches ) {
         my ( $object, $prop, $id ) = @$w;
         $object->unwatch_property( $prop, $id );
      }

      undef @$watches;
   }
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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

   my $registry = $self->{registry};

   my $object = $registry->get_by_id( $objid ) or
      return $ctx->responderr( "No such object with id $objid" );

   my $id = $object->subscribe_event( $event,
      $self->_capture_weakself( sub {
         my $self = shift;
         my $object = shift;

         my $message = $object->generate_message_EVENT( $self, $event, @_ );
         $self->request(
            request     => $message,
            on_response => sub { "IGNORE" },
         );
      } )
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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

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

   my $ctx = Net::Async::Tangence::ServerContext->new( $self, $token );

   my $registry = $self->{registry};

   $ctx->respond( Tangence::Message->new( $self, MSG_RESULT )
      ->pack_obj( $registry )
   );
}

my %change_values = (
   on_set => CHANGE_SET,
   on_add => CHANGE_ADD,
   on_del => CHANGE_DEL,
   on_push => CHANGE_PUSH,
   on_shift => CHANGE_SHIFT,
   on_splice => CHANGE_SPLICE,
   on_move => CHANGE_MOVE,
);

sub _install_watch
{
   my $self = shift;
   my ( $object, $prop ) = @_;

   my $pdef = $object->can_property( $prop );
   my $dim = $pdef->{dim};

   my %callbacks;
   foreach my $name ( @{ CHANGETYPES->{$dim} } ) {
      my $how = $change_values{$name};
      $callbacks{$name} = $self->_capture_weakself( sub {
         my $self = shift;
         my $object = shift;

         my $message = $object->generate_message_UPDATE( $self, $prop, $how, @_ );
         $self->request(
            request     => $message,
            on_response => sub { "IGNORE" },
         );
      } );
   }

   my $id = $object->watch_property( $prop, %callbacks );

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

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
