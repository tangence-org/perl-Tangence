#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Net::Async::Tangence::ServerProtocol;

use strict;
use warnings;

use base qw( Net::Async::Tangence::Protocol Tangence::Server );

our $VERSION = '0.03';

use Carp;

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->registry( delete $params->{registry} );

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
      };
   }

   $self->SUPER::configure( %params );
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
