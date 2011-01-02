#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Stream;

use strict;
use warnings;

our $VERSION = '0.02';

use base qw( IO::Async::Sequencer );

use Tangence::Constants;
use Tangence::Message;

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
         my ( $self, $token, $message ) = @_;

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

   return $self;
}

sub marshall_message
{
   my $self = shift;
   my ( $message ) = @_;

   croak "\$message is not a Tangence::Message" unless eval { $message->isa( "Tangence::Message" ) };

   return $message->bytes;
}

# Use the same method for both
{
   no strict 'refs';

   *marshall_request = \&marshall_message;
   *marshall_response = \&marshall_message;
}

sub on_read
{
   my $self = shift;
   my ( $buffref, $closed ) = @_;

   my $message = Tangence::Message->try_new_from_bytes( $self, $$buffref ) or return 0;
   my $type = $message->type;

   if( $type < 0x80 ) {
      $self->incoming_request( $message );
   }
   else {
      $self->incoming_response( $message );
   }

   return 1;
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

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
