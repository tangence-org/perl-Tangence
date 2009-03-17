package Tangence::Server::Context;

use strict;

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

1;
