package t::Ball;

use strict;

use base qw( Tangence::Object );

use Tangence::Constants;

our %METHODS = (
   bounce => {
      args => 'str',
      ret  => '',
   },
);

our %EVENTS = (
   bounced => {
      args => 'str',
   },
);

our %PROPS = (
   colour => {
      dim  => DIM_SCALAR,
      type => 'int',
   },

   size => {
      dim  => DIM_SCALAR,
      type => 'int',
      smash => 1,
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   $self->{colour} = $args{colour};
   $self->{size}   = $args{size};

   return $self;
}

sub describe
{
   my $self = shift;
   return (ref $self) . qq([colour="$self->{colour}"]);
}

our $last_bounce_ctx;

sub method_bounce
{
   my $self = shift;
   my ( $ctx, $howhigh ) = @_;
   $last_bounce_ctx = $ctx;
   $self->fire_event( "bounced", $howhigh );
   return "bouncing";
}

sub get_prop_colour
{
   my $self = shift;
   return $self->{colour};
}

sub set_prop_colour
{
   my $self = shift;
   my ( $colour ) = @_;
   $self->{colour} = $colour;
   $self->update_property( "colour", CHANGE_SET, $colour );
}

sub get_prop_size
{
   my $self = shift;
   return $self->{size};
}

sub set_prop_size
{
   my $self = shift;
   my ( $size ) = @_;
   $self->{size} = $size;
   $self->update_property( "size", CHANGE_SET, $size );
}

1;
