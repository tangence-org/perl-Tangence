#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Tangence::Client;

use strict;
use warnings;

use base qw( Tangence::Stream );

our $VERSION = '0.03';

use Carp;

use Tangence::Constants;
use Tangence::ObjectProxy;

sub _do_initial
{
   my $self = shift;
   my %args = @_;

   $self->request(
      request => Tangence::Message->new( $self, MSG_GETROOT )
         ->pack_any( $self->{identity} ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            $self->{rootobj} = $message->unpack_obj();
            $args{on_root}->( $self->{rootobj} ) if $args{on_root};
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            print STDERR "Cannot get root object - error $msg";
         }
         else {
            print STDERR "Cannot get root object - code $type\n";
         }
      }
   );

   $self->request(
      request => Tangence::Message->new( $self, MSG_GETREGISTRY ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            $self->{registry} = $message->unpack_obj();
            $args{on_registry}->( $self->{registry} ) if $args{on_registry};
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            print STDERR "Cannot get registry - error $msg";
         }
         else {
            print STDERR "Cannot get registry - code $type\n";
         }
      }
   );
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $token, $message ) = @_;

   my $objid = $message->unpack_int();

   $self->respond( $token, Tangence::Message->new( $self, MSG_OK ) );

   if( my $obj = $self->{objectproxies}->{$objid} ) {
      $obj->handle_request_EVENT( $message );
   }
}

sub handle_request_UPDATE
{
   my $self = shift;
   my ( $token, $message ) = @_;

   my $objid = $message->unpack_int();

   $self->respond( $token, Tangence::Message->new( $self, MSG_OK ) );

   if( my $obj = $self->{objectproxies}->{$objid} ) {
      $obj->handle_request_UPDATE( $message );
   }
}

sub handle_request_DESTROY
{
   my $self = shift;
   my ( $token, $message ) = @_;

   my $objid = $message->unpack_int();

   if( my $obj = $self->{objectproxies}->{$objid} ) {
      $obj->destroy;
      delete $self->{objectproxies}->{$objid};
   }

   $self->respond( $token, Tangence::Message->new( $self, MSG_OK ) );
}

sub get_root
{
   my $self = shift;
   return $self->{rootobj};
}

sub get_registry
{
   my $self = shift;
   return $self->{registry};
}

sub get_by_id
{
   my $self = shift;
   my ( $id ) = @_;

   return $self->{objectproxies}->{$id} if exists $self->{objectproxies}->{$id};

   croak "Have no proxy of object id $id";
}

sub make_proxy
{
   my $self = shift;
   my ( $id, $class, $smashdata ) = @_;

   if( exists $self->{objectproxies}->{$id} ) {
      croak "Already have an object id $id";
   }

   my $schema;
   if( defined $class ) {
      $schema = $self->{schemata}->{$class};
      defined $schema or croak "Cannot construct a proxy for class $class as no schema exists";
   }

   my $obj = $self->{objectproxies}->{$id} =
      Tangence::ObjectProxy->new(
         conn => $self,
         id   => $id,

         class  => $class,
         schema => $schema,

         on_error => $self->{on_error},
      );

   $obj->grab( $smashdata ) if defined $smashdata;

   return $obj;
}

sub make_schema
{
   my $self = shift;
   my ( $class, $schema ) = @_;

   $self->{schemata}->{$class} = $schema;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
