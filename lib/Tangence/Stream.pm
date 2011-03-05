#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2011 -- leonerd@leonerd.org.uk

package Tangence::Stream;

use strict;
use warnings;

our $VERSION = '0.04';

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

=head1 NAME

C<Tangence::Stream> - base class for C<Tangence> stream-handling mixins

=head1 DESCRIPTION

This module provides a base for L<Tangence::Client> and L<Tangence::Server>.
It is not intended to be used directly by C<Tangence> implementation code.

It provides the basic layer of message serialisation, deserialisation, and
dispatching to methods that would handle the messages. Higher level classes
are used to wrap this functionallity, and provide implementations of methods
to handle the messages received.

When a message is received, it will be passed to a method whose name depends
on the type of message received. The name will be C<handle_request_>, followed
by the name of the message type, in uppercase; for example
C<handle_request_CALL>. 

=cut

=head1 REQUIRED METHODS

The following methods are required to be implemented by some class using this
mixin.

=cut

=head2 $stream->tangence_write( $data )

Write bytes of data to the connected peer. C<$data> will be a plain perl
string.

=cut

=head2 $stream->handle_request_$TYPE( $token, $message )

Invoked on receipt of a given message type. C<$token> will be some opaque perl
scalar value, and C<$message> will be an instance of L<Tangence::Message>.

The value of the token has no particular meaning, other than to be passed to
the C<respond> method.

=cut

=head1 PROVIDED METHODS

The following methods are provided by this mixin.

=cut

# Accessors for Tangence::Message decoupling
sub peer_hasobj   { shift->{peer_hasobj} ||= {} }
sub peer_hasclass { shift->{peer_hasclass} ||= {} }

sub identity
{
   my $self = shift;
   $self->{identity} = shift if @_;
   return $self->{identity};
}

=head2 $stream->tangence_closed

Informs the object that the underlying connection has now been closed, and any
attachments to C<Tangence::Object> or C<Tangence::ObjectProxy> instances
should now be dropped.

=cut

sub tangence_closed
{
   my $self = shift;

   foreach my $id ( keys %{ $self->peer_hasobj } ) {
      my $obj = $self->get_by_id( $id );
      $obj->unsubscribe_event( "destroy", delete $self->peer_hasobj->{$id} );
   }
}

=head2 $stream->tangence_readfrom( $buffer )

Informs the object that more data has been read from the underlying connection
stream. Whole messages will be removed from the beginning of the C<$buffer>,
which should be passed as a direct scalar (because it will be modified). This
method will invoke the required C<handle_request_*> methods. Any bytes
remaining that form the start of a partial message will be left in the buffer.

=cut

sub tangence_readfrom
{
   my $self = shift;

   while( my $message = Tangence::Message->try_new_from_bytes( $self, $_[0] ) ) {
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
}

sub object_destroyed
{
   my $self = shift;
   my ( $obj, $startsub, $donesub ) = @_;

   $startsub->();

   my $objid = $obj->id;

   delete $self->peer_hasobj->{$objid};

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

=head2 $stream->request( %args )

Serialises a message object to pass to the C<tangence_write> method, then
enqueues a response handler to be invoked when a reply arrives. Takes the
following named arguments:

=over 8

=item request => Tangence::Message

The message body

=item on_response => CODE

CODE reference to the callback to be invoked when a response to the message is
received. It will be passed the response message:

 $on_response->( $message )

=back

=cut

sub request
{
   my $self = shift;
   my %args = @_;

   my $request = $args{request} or croak "Expected 'request'";
   my $on_response = $args{on_response} or croak "Expected 'on_response'";

   push @{ $self->{responder_queue} }, $on_response;

   $self->tangence_write( $request->bytes );
}

=head2 $stream->respond( $token, $message )

Serialises a message object to be sent to the C<tangence_write> method. The
C<$token> value that was passed to the C<handle_request_> method ensures that
it is sent at the correct position in the stream, to allow the peer to pair it
with the corresponding request.

=cut

sub respond
{
   my $self = shift;
   my ( $token, $message ) = @_;

   my $response = $message->bytes;

   $$token = $response;

   while( defined $self->{request_queue}[0] ) {
      $self->tangence_write( shift @{ $self->{request_queue} } );
   }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
