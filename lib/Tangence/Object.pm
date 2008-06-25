package Tangence::Object;

use strict;

use Carp;

use Tangence::Constants;

our %METHODS = (
   describe   => {
      args => '',
      ret  => 's',
   },
   can_method => {
      args => 's',
      ret  => 'h',
   },
   can_event => {
      args => 's',
      ret  => 'h',
   },
   can_property => {
      args => 's',
      ret  => 'h',
   },

   introspect => {
      args => '',
      ret  => 'h',
   },
);

our %EVENTS = (
   destroy => {
      args => '',
   },
);

our %PROPS = (
);

sub new
{
   my $class = shift;
   my %args = @_;

   defined( my $id = delete $args{id} ) or croak "Need a id";
   my $registry = delete $args{registry} or croak "Need a registry";

   my $self = bless {
      id => $id,
      registry => $registry,

      event_subs => {},   # {$event} => [ @cbs ]

      prop_watches => {}, # {$prop} => [ @cbs ]
   }, $class;

   return $self;
}

sub destroy
{
   my $self = shift;
   $self->fire_event( "destroy" );
}

sub id
{
   my $self = shift;
   return $self->{id};
}

sub describe
{
   my $self = shift;
   return ref $self;
}

sub registry
{
   my $self = shift;
   return $self->{registry};
}

sub can_method
{
   my $self = shift;
   my ( $method, $class ) = @_;

   $class ||= ref $self;

   my %methods = do { no strict 'refs'; %{$class."::METHODS"} };

   return $methods{$method} if exists $methods{$method};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $m = $self->can_method( $method, $superclass );
      return $m if $m;
   }

   return undef;
}

sub can_event
{
   my $self = shift;
   my ( $event, $class ) = @_;

   $class ||= ref $self;

   my %events = do { no strict 'refs'; %{$class."::EVENTS"} };

   return $events{$event} if exists $events{$event};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $e = $self->can_event( $event, $superclass );
      return $e if $e;
   }

   return undef;
}

sub can_property
{
   my $self = shift;
   my ( $prop, $class ) = @_;

   $class ||= ref $self;

   my %props = do { no strict 'refs'; %{$class."::PROPS"} };

   return $props{$prop} if exists $props{$prop};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $p = $self->can_property( $prop, $superclass );
      return $p if $p;
   }

   return undef;
}

sub introspect
{
   my $self = shift;
   my ( $class ) = @_;

   $class ||= ref $self;

   my %methods = do { no strict 'refs'; %{$class."::METHODS"} };
   my %events  = do { no strict 'refs'; %{$class."::EVENTS"} };
   my %props   = do { no strict 'refs'; %{$class."::PROPS"} };

   my $ret = {
      methods    => \%methods,
      events     => \%events,
      properties => \%props,
      isa        => [ $class ],
   };

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $supint = $self->introspect( $superclass );

      # Merge methods we don't yet have
      foreach my $m ( keys %{ $supint->{methods} } ) {
         next if $ret->{methods}->{$m};
         $ret->{methods}->{$m} = $supint->{methods}->{$m};
      }
      # Merge events we don't yet have
      foreach my $e ( keys %{ $supint->{events} } ) {
         next if $ret->{events}->{$e};
         $ret->{events}->{$e} = $supint->{events}->{$e};
      }
      # Merge properties we don't yet have
      foreach my $p ( keys %{ $supint->{properties} } ) {
         next if $ret->{properties}->{$p};
         $ret->{properties}->{$p} = $supint->{properties}->{$p};
      }
      # Merge the classes we don't yet have
      foreach my $c ( @{ $supint->{isa} } ) {
         next if grep { $_ eq $c } @{ $ret->{isa} };
         push @{ $ret->{isa} }, $c;
      }
   }

   return $ret;
}

sub fire_event
{
   my $self = shift;
   my ( $event, @args ) = @_;

   $self->can_event( $event ) or croak "$self has no event $event";

   foreach my $cb ( @{ $self->{event_subs}->{$event} } ) {
      $cb->( $self, $event, @args );
   }
}

sub subscribe_event
{
   my $self = shift;
   my ( $event, $callback ) = @_;

   $self->can_event( $event ) or croak "$self has no event $event";

   my $sublist = ( $self->{event_subs}->{$event} ||= [] );

   push @$sublist, $callback;

   my $ref = \@{$sublist}[$#$sublist];   # reference to last element
   return $ref + 0; # force numeric context
}

sub unsubscribe_event
{
   my $self = shift;
   my ( $event, $id ) = @_;

   my $sublist = $self->{event_subs}->{$event};

   my $index;
   for( $index = 0; $index < @$sublist; $index++ ) {
      last if \@{$sublist}[$index] + 0 == $id;
   }

   splice @$sublist, $index, 1, ();
}

sub update_property
{
   my $self = shift;
   my ( $prop, $how, @value ) = @_;

   my $pdef = $self->can_property( $prop ) or croak "$self has no property $prop";

   foreach my $cb ( @{ $self->{prop_watches}->{$prop} } ) {
      $cb->( $self, $prop, $how, @value );
   }
}

sub watch_property
{
   my $self = shift;
   my ( $prop, $callback ) = @_;

   $self->can_property( $prop ) or croak "$self has no property $prop";

   my $watchlist = ( $self->{prop_watches}->{$prop} ||= [] );

   push @$watchlist, $callback;

   my $ref = \@{$watchlist}[$#$watchlist];  # reference to last element
   return $ref + 0; # force numeric context
}

sub unwatch_property
{
   my $self = shift;
   my ( $prop, $id ) = @_;

   my $watchlist = $self->{prop_watches}->{$prop};

   my $index;
   for( $index = 0; $index < @$watchlist; $index++ ) {
      last if \@{$watchlist}[$index] + 0 == $id;
   }

   splice @$watchlist, $index, 1, ();
}

1;
