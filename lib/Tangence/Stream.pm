#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Stream;

use strict;
use warnings;

our $VERSION = '0.03';

use Carp;

use Tangence::Constants;
use Tangence::Message;

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

sub _stream_closed
{
   my $self = shift;

   foreach my $id ( keys %{ $self->{peer_hasobj} } ) {
      my $obj = $self->get_by_id( $id );
      $obj->unsubscribe_event( "destroy", delete $self->{peer_hasobj}->{$id} );
   }
}

sub read_from
{
   my $self = shift;

   while( my $message = Tangence::Message->try_new_from_bytes( $self, $_[0] ) ) {
      $self->on_message( $message );
   }
}

sub on_message
{
   my $self = shift;
   my ( $message ) = @_;

   my $type = $message->type;

   if( $type < 0x80 ) {
      push @{ $self->{request_queue} }, undef;
      my $token = \$self->{request_queue}[-1];

      my $type = $message->type;

      if( my $method = $REQ_METHOD{$type} ) {
         if( $self->can( $method ) ) {
            $self->$method( $token, $message );
         }
         else {
            $self->respondERROR( $token, sprintf( "Cannot respond to request type 0x%02x", $type ) );
         }
      }
      else {
         $self->respondERROR( $token, sprintf( "Unrecognised request type 0x%02x", $type ) );
      }
   }
   else {
      my $on_response = shift @{ $self->{responder_queue} };
      $on_response->( $message );
   }
}

sub object_destroyed
{
   my $self = shift;
   my ( $obj, $startsub, $donesub ) = @_;

   $startsub->();

   my $objid = $obj->id;

   delete $self->{peer_hasobj}->{$objid};

   $self->request(
      request => Tangence::Message->new( $self, MSG_DESTROY )
         ->pack_int( $objid ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_OK ) {
            $donesub->();
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            print STDERR "Cannot get connection $self to destroy object $objid - error $msg\n";
         }
         else {
            print STDERR "Cannot get connection $self to destroy object $objid - code $type\n";
         }
      },
   );
}

sub request
{
   my $self = shift;
   my %args = @_;

   my $request = $args{request} or croak "Expected 'request'";
   my $on_response = $args{on_response} or croak "Expected 'on_response'";

   $self->write( $request->bytes );

   push @{ $self->{responder_queue} }, $on_response;
}

sub respond
{
   my $self = shift;
   my ( $token, $message ) = @_;

   my $response = $message->bytes;

   $$token = $response;

   while( defined $self->{request_queue}[0] ) {
      $self->write( shift @{ $self->{request_queue} } );
   }
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
