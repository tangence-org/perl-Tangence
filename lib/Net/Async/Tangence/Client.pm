#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2011 -- leonerd@leonerd.org.uk

package Net::Async::Tangence::Client;

use strict;
use warnings;

use base qw( Net::Async::Tangence::Protocol Tangence::Client );

our $VERSION = '0.03';

use Carp;

use URI::Split qw( uri_split );

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   # It's possible a handle was passed in the constructor.
   $self->_do_initial( %args ) if defined $self->transport;

   return $self;
}

sub _init
{
   my $self = shift;
   my ( $params ) = @_;

   $self->{identity} = delete $params->{identity};

   $self->SUPER::_init( $params );

   $params->{on_error} ||= "croak";
}

sub configure
{
   my $self = shift;
   my %params = @_;

   if( my $on_error = delete $params{on_error} ) {
      if( ref $on_error eq "CODE" ) {
         # OK
      }
      elsif( $on_error eq "croak" ) {
         $on_error = sub { croak "Received MSG_ERROR: $_[0]" };
      }
      elsif( $on_error eq "carp" ) {
         $on_error = sub { carp "Received MSG_ERROR: $_[0]" };
      }
      else {
         croak "Expected 'on_error' to be CODE reference or strings 'croak' or 'carp'";
      }

      $self->on_error( $on_error );
   }

   $self->SUPER::configure( %params );
}

sub connect
{
   my $self = shift;
   my ( $url, %args ) = @_;

   my ( $scheme, $authority, $path, $query, $fragment ) = uri_split( $url );

   defined $scheme or croak "Invalid URL '$url'";

   if( $scheme =~ m/\+/ ) {
      $scheme =~ s/^circle\+// or croak "Found a + within URL scheme that is not 'circle+'";
   }

   if( $scheme eq "exec" ) {
      # Path will start with a leading /; we need to trim that
      $path =~ s{^/}{};
      # $query will contain args to exec - split them on +
      my @argv = split( m/\+/, $query );
      return $self->connect_exec( [ $path, @argv ], %args );
   }
   elsif( $scheme eq "ssh" ) {
      # Path will start with a leading /; we need to trim that
      $path =~ s{^/}{};
      # $query will contain args to exec - split them on +
      my @argv = split( m/\+/, $query );
      return $self->connect_ssh( $authority, [ $path, @argv ], %args );
   }
   elsif( $scheme eq "tcp" ) {
      return $self->connect_tcp( $authority, %args );
   }
   elsif( $scheme eq "unix" ) {
      return $self->connect_unix( $path, %args );
   }

   croak "Unrecognised URL scheme name '$scheme'";
}

sub connect_exec
{
   my $self = shift;
   my ( $command, %args ) = @_;

   my $loop = $self->get_loop;

   pipe( my $myread, my $childwrite ) or croak "Cannot pipe - $!";
   pipe( my $childread, my $mywrite ) or croak "Cannoe pipe - $!";

   $loop->spawn_child(
      command => $command,

      setup => [
         stdin  => $childread,
         stdout => $childwrite,
      ],

      on_exit => sub {
         print STDERR "Child exited unexpectedly\n";
      },
   );

   $self->configure(
      transport => IO::Async::Stream->new(
         read_handle  => $myread,
         write_handle => $mywrite,
      )
   );

   $args{on_connected}->( $self ) if $args{on_connected};
   $self->_do_initial( %args );
}

sub connect_ssh
{
   my $self = shift;
   my ( $host, $argv, %argv ) = @_;

   $self->connect_exec( [ "ssh", $host, @$argv ], %argv );
}

sub connect_tcp
{
   my $self = shift;
   my ( $authority, %args ) = @_;

   my ( $host, $port ) = $authority =~ m/^(.*):(.*)$/;

   $self->connect(
      host     => $host,
      service  => $port,

      on_connected => sub {
         my ( $self ) = @_;

         $args{on_connected}->( $self ) if $args{on_connected};
         $self->_do_initial( %args );
      },

      on_connect_error => sub { print STDERR "Cannot connect\n"; },
      on_resolve_error => sub { print STDERR "Cannot resolve - $_[0]\n"; },
   );
}

sub connect_unix
{
   my $self = shift;
   my ( $path, %args ) = @_;

   require Socket;

   $self->connect(
      addr => [ Socket::AF_UNIX(), Socket::SOCK_STREAM(), 0, Socket::pack_sockaddr_un( $path ) ],

      on_connected => sub {
         my ( $self ) = @_;

         $args{on_connected}->( $self ) if $args{on_connected};
         $self->_do_initial( %args );
      },

      on_connect_error => sub { print STDERR "Cannot connect\n"; },
   );
}

# Keep perl happy; keep Britain tidy
1;

__END__

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>
