package Tangence::Stream;

use strict;

use base qw( IO::Async::Sequencer );

# Import Serialisation role
use base qw( Tangence::Serialisation );

use Tangence::Constants;

use Carp;

# A map from request types to method names
# Can't use => operator because it would quote the barewords on the left, but
# we want them as constants
my %REQ_METHOD = (
   MSG_CALL,        'handle_request_CALL',
   MSG_SUBSCRIBE,   'handle_request_SUBSCRIBE',
   MSG_UNSUBSCRIBE, 'handle_request_UNSUBSCRIBE',
   MSG_EVENT,       'handle_request_EVENT',
   MSG_GETPROP,     'handle_request_GETPROP',
   MSG_SETPROP,     'handle_request_SETPROP',
   MSG_WATCH,       'handle_request_WATCH',
   MSG_UNWATCH,     'handle_request_UNWATCH',
   MSG_UPDATE,      'handle_request_UPDATE',
   MSG_DESTROY,     'handle_request_DESTROY',

   MSG_GETROOT,     'handle_request_GETROOT',
   MSG_GETREGISTRY, 'handle_request_GETREGISTRY',
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $on_closed = delete $args{on_closed};

   my $self = $class->SUPER::new(
      %args,
      on_read => \&on_read,
      marshall_request  => \&marshall_request,
      marshall_response => \&marshall_response,

      on_request => sub {
         my ( $self, $token, $req ) = @_;

         my ( $type, @data ) = @$req;

         if( my $method = $REQ_METHOD{$type} ) {
            if( $self->can( $method ) ) {
               $self->$method( $token, @data );
            }
            else {
               $self->respond( $token, [ MSG_ERROR, sprintf( "Cannot respond to request type 0x%02x", $type ) ] );
            }
         }
         else {
            $self->respond( $token, [ MSG_ERROR, sprintf( "Unrecognised request type 0x%02x", $type ) ] );
         }
      },

      on_closed => sub {
         my ( $self ) = @_;
         $on_closed->( $self ) if $on_closed;

         foreach my $id ( keys %{ $self->{peer_hasobj} } ) {
            my $obj = $self->get_by_id( $id );
            $obj->unsubscribe_event( "destroy", delete $self->{peer_hasobj}->{$id} );
         }
      },
   );

   $self->{peer_hasobj} = {}; # {$id} = $destroy_watch_id
   $self->{peer_hasclass} = {}; # {$classname} = [\@smashkeys];

   # I'm likely to use a lot of these - just make one per stream
   $self->{destroy_cb} = sub { $self->object_destroyed( @_ ) };

   return $self;
}

sub marshall_request
{
   my $self = shift;
   my ( $req ) = @_;

   my ( $type, @data ) = @$req;

   my $record = "";
   $record .= $self->pack_data( $_ ) for @data;

   return pack( "CNa*", $type, length($record), $record );
}

sub marshall_response
{
   my $self = shift;
   my ( $resp ) = @_;

   my ( $type, @data ) = @$resp;

   my $record = "";
   $record .= $self->pack_data( $_ ) for @data;

   return pack( "CNa*", $type, length($record), $record );
}

sub on_read
{
   my $self = shift;
   my ( $buffref, $closed ) = @_;

   return 0 unless length $$buffref >= 5;

   my ( $type, $len ) = unpack( "CN", $$buffref );
   return 0 unless length $$buffref >= 5 + $len;

   substr( $$buffref, 0, 5, "" );
   my $record = substr( $$buffref, 0, $len, "" );

   my @data;
   while( length $record ) {
      push @data, $self->unpack_data( $record );
   }

   if( $type < 0x80 ) {
      $self->incoming_request( [ $type, @data ] );
   }
   else {
      $self->incoming_response( [ $type, @data ] );
   }

   return 1;
}

sub object_destroyed
{
   my $self = shift;
   my ( $obj, $event, $startsub, $donesub ) = @_;

   $startsub->();

   my $objid = $obj->id;

   delete $self->{peer_hasobj}->{$objid};

   $self->request(
      request => [ MSG_DESTROY, $objid ],

      on_response => sub {
         my ( $response ) = @_;
         my $code = $response->[0];

         if( $code == MSG_OK ) {
            $donesub->();
         }
         elsif( $code == MSG_ERROR ) {
            print STDERR "Cannot get connection $self to destroy object $objid - error $response->[1]\n";
         }
         else {
            print STDERR "Cannot get connection $self to destroy object $objid - code $code\n";
         }
      },
   );
}

1;
