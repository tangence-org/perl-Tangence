package Tangence::Object;

use strict;

use Carp;

use Tangence::Constants;
use Tangence::Metacode;

our %METHODS = (
);

our %EVENTS = (
   destroy => {
      args => [],
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

   Tangence::Metacode::init_class( $class ) unless do { no strict 'refs'; defined &{"${class}::_has_Tangence"} };

   my $self = bless {
      id => $id,
      registry => $registry,

      event_subs => {},   # {$event} => [ @cbs ]

      properties => {}, # {$prop} => [ $value, \@callbacks ]
   }, $class;

   my $properties = $self->can_property();
   foreach my $prop ( keys %$properties ) {
      $self->_new_property( $prop, $properties->{$prop} );
   }

   return $self;
}

sub _new_property
{
   my $self = shift;
   my ( $prop, $pdef ) = @_;

   my $dim = $pdef->{dim};

   my $initial;

   if( my $code = $self->can( "init_prop_$prop" ) ) {
      $initial = $code->( $self );
   }
 
   elsif( $dim == DIM_SCALAR ) {
      $initial = undef;
   }
   elsif( $dim == DIM_HASH ) {
      $initial = {};
   }
   elsif( $dim == DIM_ARRAY ) {
      $initial = [];
   }
   elsif( $dim == DIM_OBJSET ) {
      $initial = {}; # these have hashes internally
   }
   else {
      croak "Unrecognised dimension $dim for property $prop";
   }

   $self->{properties}->{$prop} = [ $initial, [] ];
}

sub destroy
{
   my $self = shift;
   my %args = @_;

   $self->{destroying} = 1;

   my $outstanding = 1;

   my $on_destroyed = $args{on_destroyed};

   my $incsub = sub {
      $outstanding++
   };

   my $decsub = sub {
      --$outstanding and return;
      $self->_destroy_really;
      $on_destroyed->() if $on_destroyed;
   };

   foreach my $cb ( @{ $self->{event_subs}->{destroy} } ) {
      $cb->( $self, "destroy", $incsub, $decsub );
   }

   $decsub->();
}

sub _destroy_really
{
   my $self = shift;

   $self->registry->destroy_id( $self->id );

   undef %$self; # Now I am dead
   $self->{destroyed} = 1;
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

sub smash
{
   my $self = shift;
   my ( $smashkeys ) = @_;

   return undef unless $smashkeys and @$smashkeys;

   my @keys;
   if( ref $smashkeys eq "HASH" ) {
      @keys = keys %$smashkeys;
   }
   else {
      @keys = @$smashkeys;
   }

   return { map {
      my $m = "get_prop_$_";
      $_ => $self->$m()
   } @keys };
}

sub can_method
{
   my $self = shift;
   my ( $method, $class ) = @_;

   $class ||= ( ref $self || $self );

   my %methods = do { no strict 'refs'; %{$class."::METHODS"} };

   return $methods{$method} if defined $method and exists $methods{$method};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $m = $self->can_method( $method, $superclass );
      if( defined $method ) {
         return $m if $m;
      }
      else {
         exists $methods{$_} or $methods{$_} = $m->{$_} for keys %$m;
      }
   }

   return \%methods unless defined $method;
   return undef;
}

sub can_event
{
   my $self = shift;
   my ( $event, $class ) = @_;

   $class ||= ( ref $self || $self );

   my %events = do { no strict 'refs'; %{$class."::EVENTS"} };

   return $events{$event} if defined $event and exists $events{$event};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $e = $self->can_event( $event, $superclass );
      if( defined $event ) {
         return $e if $e;
      }
      else {
         exists $events{$_} or $events{$_} = $e->{$_} for keys %$e;
      }
   }

   return \%events unless defined $event;
   return undef;
}

sub can_property
{
   my $self = shift;
   my ( $prop, $class ) = @_;

   $class ||= ( ref $self || $self );

   my %props = do { no strict 'refs'; %{$class."::PROPS"} };

   return $props{$prop} if defined $prop and exists $props{$prop};

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $p = $self->can_property( $prop, $superclass );
      if( defined $prop ) {
         return $p if $p;
      }
      else {
         exists $props{$_} or $props{$_} = $p->{$_} for keys %$p;
      }
   }

   return \%props unless defined $prop;
   return undef;
}

sub smashkeys
{
   my $self = shift;
   my ( $class ) = @_;

   $class ||= ( ref $self || $self );

   my %props = do { no strict 'refs'; %{$class."::PROPS"} };

   my %smash;

   $props{$_}->{smash} and $smash{$_} = 1 for keys %props;

   my @isa = do { no strict 'refs'; @{$class."::ISA"} };

   foreach my $superclass ( @isa ) {
      my $supkeys = $self->smashkeys( $superclass );

      # Merge keys we don't yet have
      $smash{$_} = 1 for keys %$supkeys;
   }

   return \%smash;
}

sub introspect
{
   my $self = shift;

   my $class = ( ref $self || $self );

   my $ret = {
      methods    => $self->can_method(),
      events     => $self->can_event(),
      properties => $self->can_property(),
      isa        => [ $class, do { no strict 'refs'; @{$class."::ISA"} } ],
   };

   return $ret;
}

sub fire_event
{
   my $self = shift;
   my ( $event, @args ) = @_;

   $event eq "destroy" and croak "$self cannot fire destroy event directly";

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

   foreach my $cb ( @{ $self->{properties}->{$prop}->[1] } ) {
      $cb->( $self, $prop, $how, @value );
   }
}

sub watch_property
{
   my $self = shift;
   my ( $prop, $callback ) = @_;

   $self->can_property( $prop ) or croak "$self has no property $prop";

   my $watchlist = $self->{properties}->{$prop}->[1];

   push @$watchlist, $callback;

   my $ref = \@{$watchlist}[$#$watchlist];  # reference to last element
   return $ref + 0; # force numeric context
}

sub unwatch_property
{
   my $self = shift;
   my ( $prop, $id ) = @_;

   my $watchlist = $self->{properties}->{$prop}->[1];

   my $index;
   for( $index = 0; $index < @$watchlist; $index++ ) {
      last if \@{$watchlist}[$index] + 0 == $id;
   }

   splice @$watchlist, $index, 1, ();
}

1;
