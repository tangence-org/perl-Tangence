#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Server::Context;

use strict;
use warnings;

use Carp;

use Tangence::Constants;

sub new
{
   my $class = shift;
   my ( $conn, $token ) = @_;

   return bless {
      conn  => $conn,
      token => $token,
   }, $class;
}

sub DESTROY
{
   my $self = shift;
   $self->{responded} or croak "$self never responded";
}

sub connection
{
   my $self = shift;
   return $self->{conn};
}

sub respond
{
   my $self = shift;
   my ( $message ) = @_;

   $self->{responded} and croak "$self has responded once already";

   my $conn = $self->{conn};
   $conn->respond( $self->{token}, $message );

   $self->{responded} = 1;

   return;
}

sub responderr
{
   my $self = shift;
   my ( $msg ) = @_;

   $self->respond( Tangence::Message->new( $self->{conn}, MSG_ERROR )
      ->pack_str( $msg )
   );
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
