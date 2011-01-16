#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Net::Async::Tangence::Server;

use strict;
use warnings;

use base qw( IO::Async::Listener );

our $VERSION = '0.02';

use Carp;

use Scalar::Util qw( weaken );

use Net::Async::Tangence::ServerProtocol;

sub new
{
   my $class = shift;
   my %args = @_;

   my $loop = delete $args{loop};

   my $self = $class->SUPER::new( %args );

   $loop->add( $self ) if $loop;

   return $self;
}

sub _init
{
   my $self = shift;
   my ( $params ) = @_;
   $self->SUPER::_init( $params );

   $params->{on_stream} = sub {
      my ( $self, $stream ) = @_;

      $self->new_conn( stream => $stream );
   };

   $self->{registry} = delete $params->{registry} if exists $params->{registry};
}

sub new_conn
{
   my $self = shift;
   my %args = @_;

   my $stream = $args{stream} ||
                $args{handle} && IO::Async::Stream->new( handle => $args{handle} );

   weaken( my $weakself = $self );

   my $conn = Net::Async::Tangence::ServerProtocol->new(
      transport => $stream,
      registry => $self->{registry},
      on_closed => sub {
         $weakself->remove_child( $_[0] );
      },
   );

   $self->add_child( $conn );

   return $conn;
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
