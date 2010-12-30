#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package Tangence::Connection;

use strict;
use warnings;

use base qw( Tangence::Stream );
use Tangence::Constants;

use Carp;

use Tangence::ObjectProxy;

use URI::Split qw( uri_split );

sub new
{
   my $class = shift;
   my %args = @_;

   my $identity = delete $args{identity};

   my $on_error = delete $args{on_error} || "croak";
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

   my $self = $class->SUPER::new( %args );

   $self->{objectproxies} = {};
   $self->{schemata}      = {};

   $self->{identity} = $identity;
   $self->{on_error} = $on_error;

   # It's possible a handle was passed in the constructor.
   $self->_do_initial( %args ) if defined $self->read_handle;

   return $self;
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

   $self->set_handles(
      read_handle  => $myread,
      write_handle => $mywrite,
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

   my $loop = $self->get_loop;

   require Socket;

   $loop->connect(
      socktype => Socket::SOCK_STREAM(),
      host     => $host,
      service  => $port,

      on_connected => sub {
         my ( $sock ) = @_;

         $self->set_handle( $sock );

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

   my $loop = $self->get_loop;

   require Socket;

   $loop->connect(
      addr => [ Socket::AF_UNIX(), Socket::SOCK_STREAM(), 0, Socket::pack_sockaddr_un( $path ) ],

      on_connected => sub {
         my ( $sock ) = @_;

         $self->set_handle( $sock );

         $args{on_connected}->( $self ) if $args{on_connected};
         $self->_do_initial( %args );
      },

      on_connect_error => sub { print STDERR "Cannot connect\n"; },
   );
}

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
