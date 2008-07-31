package Tangence::Connection;

use strict;

use base qw( Tangence::Stream );
use Tangence::Constants;

use Carp;

use Tangence::ObjectProxy;

use URI::Split qw( uri_split );

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->{objectproxies} = {};

   # Default
   $args{on_error} = "croak" if !$args{on_error};

   my $on_error;
   if( ref $args{on_error} eq "CODE" ) {
      $on_error = $args{on_error};
   }
   elsif( $args{on_error} eq "croak" ) {
      $on_error = sub { croak "Received MSG_ERROR: $_[0]" };
   }
   elsif( $args{on_error} eq "carp" ) {
      $on_error = sub { carp "Received MSG_ERROR: $_[0]" };
   }
   else {
      croak "Expected 'on_error' to be CODE reference or strings 'croak' or 'carp'";
   }

   $self->{on_error} = $on_error;

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
      },

      on_connect_error => sub { print STDERR "Cannot connect\n"; },
   );
}

sub subscribe
{
   my $self = shift;
   my ( $objid, $event, $callback ) = @_;

   if( exists $self->{subscriptions}->{$objid}->{$event} ) {
      croak "Cannot subscribe to event $event on object $objid - already subscribed";
   }

   $self->{subscriptions}->{$objid}->{$event} = undef;

   $self->request(
      request => [ MSG_SUBSCRIBE, $objid, $event ],

      on_response => sub {
         my ( $response ) = @_;
         my $code = $response->[0];

         if( $code == MSG_SUBSCRIBED ) {
            $self->{subscriptions}->{$objid}->{$event} = $callback;
         }
         elsif( $code == MSG_ERROR ) {
            print STDERR "Cannot subscribe to event '$event' on object $objid - error $response->[1]\n";
         }
         else {
            print STDERR "Cannot subscribe to event '$event' on object $objid - code $code\n";
         }
      },
   );
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $token, $objid, $event, @args ) = @_;

   $self->respond( $token, [ MSG_OK ] );

   my $callback = $self->{subscriptions}->{$objid}->{$event};

   if( $callback ) {
      $callback->( $objid, $event, @args );
   }
   else {
      print STDERR "Got spurious EVENT $event on object $objid: " . join( ", ", @args ) . "\n";
   }
}

sub watch
{
   my $self = shift;
   my ( $objid, $prop, $callback, $want_initial ) = @_;

   if( exists $self->{watches}->{$objid}->{$prop} ) {
      croak "Cannot watch property $prop on object $objid - already watching";
   }

   $self->{watches}->{$objid}->{$prop} = undef;

   $self->request(
      request => [ MSG_WATCH, $objid, $prop, ! !$want_initial ],

      on_response => sub {
         my ( $response ) = @_;
         my $code = $response->[0];

         if( $code == MSG_WATCHING ) {
            $self->{watches}->{$objid}->{$prop} = $callback;
         }
         elsif( $code == MSG_ERROR ) {
            print STDERR "Cannot watch property '$prop' on object $objid - error $response->[1]\n";
         }
         else {
            print STDERR "Cannot watch property '$prop' on object $objid - code $code\n";
         }
      },
   );
}

sub handle_request_UPDATE
{
   my $self = shift;
   my ( $token, $objid, $prop, $how, @value ) = @_;

   $self->respond( $token, [ MSG_OK ] );

   my $callback = $self->{watches}->{$objid}->{$prop};

   if( $callback ) {
      $callback->( $objid, $prop, $how, @value );
   }
   else {
      print STDERR "Got spurious UPDATE $how $prop on object $objid: " . join( ", ", @value ) . "\n";
   }
}

sub get_by_id
{
   my $self = shift;
   my ( $id ) = @_;

   return $self->make_proxy( $id );
}

sub make_proxy
{
   my $self = shift;
   my ( $objid ) = @_;

   return $self->{objectproxies}->{$objid} ||=
      Tangence::ObjectProxy->new(
         conn => $self,
         id   => $objid,

         on_error => $self->{on_error},
      );
}

1;
