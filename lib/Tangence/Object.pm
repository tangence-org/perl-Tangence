package Tangence::Object;

use strict;

use Carp;

use Tangence::Constants;

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

   $class->_init_class unless do { no strict 'refs'; defined &{"${class}::_has_Tangence"} };

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

   $self->{properties}->{$prop} = [ undef, [] ];
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

####
# META code
####

sub _init_class
{
   my $class = shift;

   # This method does lots of evilness. But we'll try to keep it brief, and
   # all in one place
   no strict 'refs';

   foreach my $superclass ( @{$class."::ISA"} ) {
      # Not every superclass might be a Tangence::Object
      _init_class( $superclass ) unless defined &{"${superclass}::_has_Tangence"};
   }

   my %subs = (
      _has_Tangence => sub() { 1 },
   );

   my %props = %{$class."::PROPS"};

   foreach my $prop ( keys %props ) {
      my $pdef = $props{$prop};

      _init_class_property( $class, $prop, $pdef, \%subs );
   }

   foreach my $name ( keys %subs ) {
      next if defined &{"${class}::${name}"};
      *{"${class}::${name}"} = $subs{$name};
   }
}

sub _init_class_property
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"get_prop_$prop"} = sub {
      my $self = shift;
      return $self->{properties}->{$prop}->[0]
   };

   $subs->{"set_prop_$prop"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$prop}->[0] = $newval;
      $self->update_property( $prop, CHANGE_SET, $newval );
   };

   my $dim = $pdef->{dim};

   if( $dim == DIM_SCALAR ) {
      _init_class_property_scalar( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_HASH ) {
      _init_class_property_hash( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_ARRAY ) {
      _init_class_property_array( $class, $prop, $pdef, $subs );
   }
   elsif( $dim == DIM_OBJSET ) {
      _init_class_property_objset( $class, $prop, $pdef, $subs );
   }
   else {
      croak "Unrecognised property dimension $dim for $class :: $prop";
   }
}

sub _init_class_property_scalar
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   # Nothing needed
}

sub _init_class_property_hash
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"add_prop_$prop"} = sub {
      my $self = shift;
      my ( $key, $value ) = @_;
      $self->{properties}->{$prop}->[0]->{$key} = $value;
      $self->update_property( $prop, CHANGE_ADD, $key, $value );
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $key ) = @_;
      delete $self->{properties}->{$prop}->[0]->{$key};
      $self->update_property( $prop, CHANGE_DEL, $key );
   };
}

sub _init_class_property_array
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   $subs->{"push_prop_$prop"} = sub {
      my $self = shift;
      my @values = @_;
      push @{ $self->{properties}->{$prop}->[0] }, @values;
      $self->update_property( $prop, CHANGE_PUSH, @values );
   };

   $subs->{"shift_prop_$prop"} = sub {
      my $self = shift;
      my ( $count ) = @_;
      $count = 1 unless @_;
      splice @{ $self->{properties}->{$prop}->[0] }, 0, $count, ();
      $self->update_property( $prop, CHANGE_SHIFT, $count );
   };

   $subs->{"splice_prop_$prop"} = sub {
      my $self = shift;
      my ( $index, $count, @values ) = @_;
      splice @{ $self->{properties}->{$prop}->[0] }, $index, $count, @values;
      $self->update_property( $prop, CHANGE_SPLICE, $index, $count, @values );
   };
}

sub _init_class_property_objset
{
   my ( $class, $prop, $pdef, $subs ) = @_;

   # Different set method
   $subs->{"set_prop_$prop"} = sub {
      my $self = shift;
      my ( $newval ) = @_;
      $self->{properties}->{$prop}->[0] = $newval;
      $self->update_property( $prop, CHANGE_SET, [ values %$newval ] );
   };

   $subs->{"add_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj ) = @_;
      $self->{properties}->{$prop}->[0]->{$obj->id} = $obj;
      $self->update_property( $prop, CHANGE_ADD, $obj );
   };

   $subs->{"del_prop_$prop"} = sub {
      my $self = shift;
      my ( $obj_or_id ) = @_;
      my $id = ref $obj_or_id ? $obj_or_id->id : $obj_or_id;
      delete $self->{properties}->{$prop}->[0]->{$id};
      $self->update_property( $prop, CHANGE_DEL, $id );
   };
}

1;
