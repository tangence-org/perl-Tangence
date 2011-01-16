#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Net::Async::Tangence::Server;

use strict;
use warnings;

use IO::Async::Listener '0.36';
use base qw( IO::Async::Listener );

our $VERSION = '0.03';

use Carp;

use Net::Async::Tangence::ServerProtocol;

sub _init
{
   my $self = shift;
   my ( $params ) = @_;
   $self->SUPER::_init( $params );

   $self->{registry} = delete $params->{registry} if exists $params->{registry};
}

sub on_stream
{
   my $self = shift;
   my ( $stream ) = @_;

   my $conn = Net::Async::Tangence::ServerProtocol->new(
      transport => $stream,
      registry => $self->{registry},
      on_closed => $self->_capture_weakself( sub {
         my $self = shift;
         $self->remove_child( $_[0] );
      } ),
   );

   $self->add_child( $conn );

   return $conn;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
