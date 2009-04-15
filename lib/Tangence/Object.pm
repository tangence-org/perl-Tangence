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
   elsif( $dim == DIM_QUEUE or $dim == DIM_ARRAY ) {
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
      $cb->( $incsub, $decsub );
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
      $cb->( @args );
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

sub watch_property
{
   my $self = shift;
   my ( $prop, %callbacks ) = @_;

   my $pdef = $self->can_property( $prop ) or croak "$self has no property $prop";

   my $callbacks = {};
   foreach my $name ( @{ CHANGETYPES->{$pdef->{dim}} } ) {
      ref( $callbacks->{$name} = delete $callbacks{$name} ) eq "CODE"
         or croak "Expected '$name' as a CODE ref";
   }

   my $watchlist = $self->{properties}->{$prop}->[1];

   push @$watchlist, $callbacks;

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

### Message handling

sub handle_request_CALL
{
   my $self = shift;
   my ( $ctx, $message ) = @_;

   my $method = $message->unpack_str();

   my $mdef = $self->can_method( $method ) or die "Object cannot respond to method $method\n";

   my $m = "method_$method";
   $self->can( $m ) or die "Object cannot run method $method\n";

   my @args = $message->unpack_all_typed( $mdef->{args} );

   my $result = $self->$m( $ctx, @args );

   my $response = Tangence::Message->new( $ctx->connection, MSG_RESULT );
   $response->pack_typed( $mdef->{ret}, $result ) if $mdef->{ret};

   return $response;
}

sub generate_message_EVENT
{
   my $self = shift;
   my ( $conn, $event, @args ) = @_;

   my $edef = $self->can_event( $event ) or die "Object cannot respond to event $event";

   return Tangence::Message->new( $conn, MSG_EVENT )
      ->pack_int( $self->id )
      ->pack_str( $event )
      ->pack_all_typed( $edef->{args}, @args );
}

sub handle_request_GETPROP
{
   my $self = shift;
   my ( $ctx, $message ) = @_;

   my $prop = $message->unpack_str();

   my $pdef = $self->can_property( $prop ) or die "Object does not have property $prop";

   my $m = "get_prop_$prop";
   $self->can( $m ) or die "Object cannot get property $prop\n";

   my $result = $self->$m();

   return Tangence::Message->new( $ctx->connection, MSG_RESULT )
      ->pack_any( $result );
}

sub handle_request_SETPROP
{
   my $self = shift;
   my ( $ctx, $message ) = @_;

   my $prop  = $message->unpack_str();
   my $value = $message->unpack_any();

   my $pdef = $self->can_property( $prop ) or die "Object does not have property $prop\n";

   my $m = "set_prop_$prop";
   $self->can( $m ) or die "Object cannot set property $prop\n";

   $self->$m( $value );

   return Tangence::Message->new( $self, MSG_OK );
}

sub generate_message_UPDATE
{
   my $self = shift;
   my ( $conn, $prop, $how, @args ) = @_;

   my $pdef = $self->can_property( $prop ) or die "Object does not have property $prop\n";
   my $dim = $pdef->{dim};

   my $message = Tangence::Message->new( $conn, MSG_UPDATE )
      ->pack_int( $self->id )
      ->pack_str( $prop )
      ->pack_typed( "u8", $how );

   my $dimname = DIMNAMES->[$dim];
   if( my $code = $self->can( "_generate_message_UPDATE_$dimname" ) ) {
      $code->( $self, $message, $how, $pdef->{type}, @args );
   }
   else {
      croak "Unrecognised property dimension $dim for $prop";
   }

   return $message;
}

sub _generate_message_UPDATE_scalar
{
   my $self = shift;
   my ( $message, $how, $type, @args ) = @_;

   if( $how == CHANGE_SET ) {
      my ( $value ) = @args;
      $message->pack_typed( $type, $value );
   }
   else {
      croak "Change type $how is not valid for a scalar property";
   }
}

sub _generate_message_UPDATE_hash
{
   my $self = shift;
   my ( $message, $how, $type, @args ) = @_;

   if( $how == CHANGE_SET ) {
      my ( $value ) = @args;
      $message->pack_typed( "dict($type)", $value );
   }
   elsif( $how == CHANGE_ADD ) {
      my ( $key, $value ) = @args;
      $message->pack_str( $key );
      $message->pack_typed( $type, $value );
   }
   elsif( $how == CHANGE_DEL ) {
      my ( $key ) = @args;
      $message->pack_str( $key );
   }
   else {
      croak "Change type $how is not valid for a hash property";
   }
}

sub _generate_message_UPDATE_queue
{
   my $self = shift;
   my ( $message, $how, $type, @args ) = @_;

   if( $how == CHANGE_SET ) {
      my ( $value ) = @args;
      $message->pack_typed( "list($type)", $value );
   }
   elsif( $how == CHANGE_PUSH ) {
      $message->pack_all_sametype( $type, @args );
   }
   elsif( $how == CHANGE_SHIFT ) {
      my ( $count ) = @args;
      $message->pack_int( $count );
   }
   else {
      croak "Change type $how is not valid for a queue property";
   }
}

sub _generate_message_UPDATE_array
{
   my $self = shift;
   my ( $message, $how, $type, @args ) = @_;

   if( $how == CHANGE_SET ) {
      my ( $value ) = @args;
      $message->pack_typed( "list($type)", $value );
   }
   elsif( $how == CHANGE_PUSH ) {
      $message->pack_all_sametype( $type, @args );
   }
   elsif( $how == CHANGE_SHIFT ) {
      my ( $count ) = @args;
      $message->pack_int( $count );
   }
   elsif( $how == CHANGE_SPLICE ) {
      my ( $start, $count, @values ) = @args;
      $message->pack_int( $start );
      $message->pack_int( $count );
      $message->pack_all_sametype( $type, @values );
   }
   else {
      croak "Change type $how is not valid for an array property";
   }
}

sub _generate_message_UPDATE_objset
{
   my $self = shift;
   my ( $message, $how, $type, @args ) = @_;

   if( $how == CHANGE_SET ) {
      my ( $value ) = @args;
      # This will arrive in a plain LIST ref
      $message->pack_typed( "list($type)", $value );
   }
   elsif( $how == CHANGE_ADD ) {
      my ( $value ) = @_;
      $message->pack_typed( $type, $value );
   }
   elsif( $how == CHANGE_DEL ) {
      my ( $id ) = @_;
      $message->pack_int( $id );
   }
   else {
      croak "Change type $how is not valid for an objset property";
   }
}

1;
