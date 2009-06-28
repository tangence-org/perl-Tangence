package Tangence::Server;

use strict;

use Carp;

use Scalar::Util qw( weaken );

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
      conns    => [],
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

   weaken( my $weakself = $self );

   my $conn = Tangence::Server::Connection->new( %args,
      registry => $self->{registry},
      on_closed => sub { $weakself->del_conn( @_ ) },
   );

   $self->{loop}->add( $conn );

   push @{ $self->{conns} }, $conn;

   return $conn;
}

sub del_conn
{
   my $self = shift;
   my ( $conn ) = @_;

   my $conns = $self->{conns};
   my $idx;
   $conns->[$_] == $conn and $idx = $_, last for 0 .. $#$conns;

   defined $idx and splice @$conns, $idx, 1;
}

sub DESTROY
{
   my $self = shift;

   foreach my $conn ( @{ $self->{conns} } ) {
      $conn->shutdown;
      $conn->close;
   }
}

1;
