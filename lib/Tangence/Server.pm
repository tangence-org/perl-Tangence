package Tangence::Server;

use strict;

use Carp;

use Tangence::Server::Connection;

sub new
{
   my $class = shift;
   my %args = @_;

   my $loop     = delete $args{loop} or croak "Need a 'loop'";
   my $registry = delete $args{registry} or croak "Need a 'registry'";

   my $self = bless {
      loop     => $loop,
      registry => $registry,
   }, $class;

   return $self;
}

sub listen
{
   my $self = shift;
   my %listenargs = @_;

   my $loop = $self->{loop};

   $loop->listen(
      %listenargs,

      on_accept => sub { $self->new_conn( handle => $_[0] ) },
   );
}

sub new_conn
{
   my $self = shift;
   my %args = @_;

   my $be = Tangence::Server::Connection->new( %args,
      registry => $self->{registry},
   );

   $self->{loop}->add( $be );

   return $be;
}

1;
