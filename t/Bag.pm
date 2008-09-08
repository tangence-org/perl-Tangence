package t::Bag;

use strict;

use base qw( Tangence::Object );

use Tangence::Constants;

our %METHODS = (
   get_ball => {
      args => 's',
      ret  => 'o',
   },

   pull_ball => {
      args => 's',
      ret  => 'o',
   },

   add_ball => {
      args => 'o',
      ret  => '',
   },
);

our %PROPS = (
   colours => {
      dim  => DIM_HASH,
      type => 'i',
   },
);

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = $class->SUPER::new( %args );

   my $colours = $args{colours};

   my $registry = $self->registry;

   $self->{balls} = [ map { $registry->construct( "t::Ball", colour => $_, size => $args{size} ) } @$colours ];

   return $self;
}

sub describe
{
   my $self = shift;
   my $balls = scalar @{ $self->{balls} };
   return (ref $self) . "[with $balls balls]";
}

sub method_get_ball
{
   my $self = shift;
   my ( $ctx, $colour ) = @_;

   my $balls = $self->{balls};

   foreach my $ball ( @$balls ) {
      if( $ball->get_prop_colour eq $colour ) {
         return $ball;
      }
   }

   return undef;
}

sub method_pull_ball
{
   my $self = shift;
   my ( $ctx, $colour ) = @_;

   my $balls = $self->{balls};

   foreach my $i ( 0 .. $#$balls ) {
      if( $balls->[$i]->get_prop_colour eq $colour ) {
         my ( $ball ) = splice( @$balls, $i, 1 );
         return $ball;
      }
   }

   return undef;
}

sub method_add_ball
{
   my $self = shift;
   my ( $ctx, $ball ) = @_;

   push @{ $self->{balls} }, $ball;

   return;
}

sub get_prop_colours
{
   my $self = shift;

   my %colours;

   foreach my $ball ( @{ $self->{balls} } ) {
      $colours{$ball->get_prop_colour}++;
   }

   return \%colours;
}

1;
