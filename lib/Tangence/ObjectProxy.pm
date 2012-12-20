#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2012 -- leonerd@leonerd.org.uk

package Tangence::ObjectProxy;

use strict;
use warnings;

our $VERSION = '0.13';

use Carp;

use Tangence::Constants;

use Tangence::Meta::Type;

use constant TYPE_U8 => Tangence::Meta::Type->new( "u8" );

use Scalar::Util qw( weaken );

=head1 NAME

C<Tangence::ObjectProxy> - proxy for a C<Tangence> object in a
C<Tangence::Client>

=head1 DESCRIPTION

Instances in this class act as a proxy for an object in the
L<Tangence::Server>, allowing methods to be called, events to be subscribed
to, and properties to be watched.

These objects are not directly constructed by calling the C<new> class method;
instead they are returned by methods on L<Tangence::Client>, or by methods on
other C<Tangence::ObjectProxy> instances. Ultimately every object proxy that a
client uses will come from either the proxy to the registry, or the root
object.

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = bless {
      conn => $args{conn},
      id   => $args{id},

      class  => $args{class},
      introspection => $args{introspection},

      on_error => $args{on_error},
   }, $class;

   # An ObjectProxy is useless after its connection disappears
   weaken( $self->{conn} );

   return $self;
}

sub destroy
{
   my $self = shift;

   $self->{destroyed} = 1;

   foreach my $cb ( @{ $self->{subscriptions}->{destroy} } ) {
      $cb->();
   }

   undef %$self;
   $self->{destroyed} = 1;
}

=head1 METHODS

=cut

use overload '""' => \&STRING;

sub STRING
{
   my $self = shift;
   return "Tangence::ObjectProxy[id=$self->{id}]";
}

=head2 $id = $proxy->id

Returns the object ID for the C<Tangence> object being proxied for.

=cut

sub id
{
   my $self = shift;
   return $self->{id};
}

=head2 $classname = $proxy->class

Returns the name of the class of the C<Tangence> object being proxied for.

=cut

sub class
{
   my $self = shift;
   return $self->{class};
}

sub introspect
{
   my $self = shift;
   if( !@_ ) {
      return $self->{introspection};
   }
   else {
      my $section = shift;
      return $self->{introspection}->{$section};
   }
}

sub can_method
{
   my $self = shift;
   my ( $method ) = @_;
   return $self->{introspection}->{methods}->{$method};
}

sub can_event
{
   my $self = shift;
   my ( $event ) = @_;
   return $self->{introspection}->{events}->{$event};
}

sub can_property
{
   my $self = shift;
   my ( $property ) = @_;
   return $self->{introspection}->{properties}->{$property};
}

# Don't want to call it "isa"
sub proxy_isa 
{
   my $self = shift;
   if( @_ ) {
      my ( $class ) = @_;
      return !! grep { $_ eq $class } @{ $self->{introspection}->{isa} };
   }
   else {
      return @{ $self->{introspection}->{isa} };
   }
}

sub grab
{
   my $self = shift;
   my ( $smashdata ) = @_;

   foreach my $property ( keys %{ $smashdata } ) {
      my $value = $smashdata->{$property};
      my $dim = $self->{introspection}->{properties}->{$property}->{dim};

      if( $dim == DIM_OBJSET ) {
         # Comes across in a LIST. We need to map id => obj
         $value = { map { $_->id => $_ } @$value };
      }

      my $prop = $self->{props}->{$property} ||= {};
      $prop->{cache} = $value;
   }
}

=head2 $proxy->call_method( %args )

Calls the given method on the server object and invokes a callback function
when a result is received.

Takes the following named arguments:

=over 8

=item method => STRING

The name of the method

=item args => ARRAY

Optional. If provided, gives positional arguments for the method.

=item on_result => CODE

Callback function to invoke when a result is returned

 $on_result->( $result )

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

=cut

sub call_method
{
   my $self = shift;
   my %args = @_;

   my $method = delete $args{method} or croak "Need a method";
   my $args   = delete $args{args};

   ref( my $on_result = delete $args{on_result} ) eq "CODE" 
      or croak "Expected 'on_result' as a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $mdef = $self->can_method( $method );
   croak "Class ".$self->class." does not have a method $method" unless $mdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_CALL )
         ->pack_int( $self->id )
         ->pack_str( $method )
         ->pack_all_typed( $mdef->{args}, $args ? @$args : () ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            my $result = $mdef->{ret} ? $message->unpack_typed( $mdef->{ret} )
                                      : undef;
            $on_result->( $result );
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

=head2 $proxy->subscribe_event( %args )

Subscribes to the given event on the server object, installing a callback
function which will be invoked whenever the event is fired.

Takes the following named arguments:

=over 8

=item event => STRING

Name of the event

=item on_fire => CODE

Callback function to invoke whenever the event is fired

 $on_fire->( @args )

=item on_subscribed => CODE

Optional. Callback function to invoke once the event subscription is
successfully installed by the server.

 $on_subscribed->()

If this is provided, it is guaranteed to be invoked before any invocation of
the C<on_fire> event handler.

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

=cut

sub subscribe_event
{
   my $self = shift;
   my %args = @_;

   my $event = delete $args{event} or croak "Need a event";
   ref( my $callback = delete $args{on_fire} ) eq "CODE"
      or croak "Expected 'on_fire' as a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $on_subscribed = $args{on_subscribed};

   my $edef = $self->can_event( $event );
   croak "Class ".$self->class." does not have an event $event" unless $edef;

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      push @$cbs, $callback;
      return;
   }

   my @cbs = ( $callback );
   $self->{subscriptions}->{$event} = \@cbs;

   return if $event eq "destroy"; # This is automatically handled

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_SUBSCRIBE )
         ->pack_int( $self->id )
         ->pack_str( $event ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_SUBSCRIBED ) {
            $on_subscribed->() if $on_subscribed;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $message ) = @_;

   my $event = $message->unpack_str();
   my $edef = $self->can_event( $event ) or return;

   my @args = $message->unpack_all_typed( $edef->{args} );

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      foreach my $cb ( @$cbs ) { $cb->( @args ) }
   }
}

=head2 $proxy->get_property( %args )

Requests the current value of the property from the server object, and invokes
a callback function when the value is received.

Takes the following named arguments

=over 8

=item property => STRING

The name of the property

=item on_value => CODE

Callback function to invoke when the value is returned

 $on_value->( $value )

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

=cut

sub get_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   ref( my $on_value = delete $args{on_value} ) eq "CODE" 
      or croak "Expected 'on_value' as a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_GETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_RESULT ) {
            my $value = $message->unpack_any();
            $on_value->( $value );
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

=head2 $value = $proxy->prop( $property )

Returns the locally-cached value of a smashed property. If the named property
is not a smashed property, an exception is thrown.

=cut

sub prop
{
   my $self = shift;
   my ( $property ) = @_;

   if( exists $self->{props}->{$property}->{cache} ) {
      return $self->{props}->{$property}->{cache};
   }

   croak "$self does not have a cached property '$property'";
}

=head2 $proxy->set_property( %args )

Sets the value of the property in the server object. Optionally invokes a
callback function when complete.

Takes the following named arguments

=over 8

=item property => STRING

The name of the property

=item value => SCALAR

New value to set for the property

=item on_done => CODE

Optional. Callback function to invoke once the new value is set.

 $on_done->()

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

=cut

sub set_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   my $on_done = delete $args{on_done};
   !defined $on_done or ref $on_done eq "CODE"
      or croak "Expected 'on_done' to be a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   # value can quite legitimately be undef
   exists $args{value} or croak "Need a value";
   my $value = delete $args{value};

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_SETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_any( $value ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_OK ) {
            $on_done->() if $on_done;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

=head2 $proxy->watch_property( %args )

Watches the given property on the server object, installing callback functions
which will be invoked whenever the property value changes.

Takes the following named arguments:

=over 8

=item property => STRING

Name of the property

=item want_initial => BOOLEAN

Optional. If true, requests that the server send the current value of the
property at the time the watch is installed, in an C<on_set> event. This is
performed atomically with installing watch.

=item on_watched => CODE

Optional. Callback function to invoke once the property watch is
successfully installed by the server.

 $on_watched->()

If this is provided, it is guaranteed to be invoked before any invocation of
the value change handlers.

=item on_updated => CODE

Optional. Callback function to invoke whenever the property value changes.

 $on_updated->( $new_value )

If not provided, then individual handlers for individual change types must be
provided.

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

The set of callback functions that are required depends on the type of the
property. These are documented in the C<watch_property> method of
L<Tangence::Object>.

=cut

sub watch_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $want_initial = delete $args{want_initial};

   my $on_watched = $args{on_watched};

   my $pdef = $self->can_property( $property );
   croak "Class ".$self->class." does not have a property $property" unless $pdef;

   my $callbacks = {};
   my $on_updated = delete $args{on_updated};
   if( $on_updated ) {
      ref $on_updated eq "CODE" or croak "Expected 'on_updated' to be a CODE ref";
      $callbacks->{on_updated} = $on_updated;
   }

   foreach my $name ( @{ CHANGETYPES->{$pdef->{dim}} } ) {
      # All of these become optional if 'on_updated' is supplied
      next if $on_updated and not exists $args{$name};

      ref( $callbacks->{$name} = delete $args{$name} ) eq "CODE"
         or croak "Expected '$name' as a CODE ref";
   }

   # Smashed properties behave differently
   my $smash = $pdef->{smash};

   if( my $cbs = $self->{props}->{$property}->{cbs} ) {
      if( $want_initial and !$smash ) {
         $self->get_property(
            property => $property,
            on_value => sub {
               $callbacks->{on_set} and $callbacks->{on_set}->( $_[0] );
               $callbacks->{on_updated} and $callbacks->{on_updated}->( $_[0] );
               push @$cbs, $callbacks;
               $on_watched->() if $on_watched;
            },
         );
      }
      elsif( $want_initial and $smash ) {
         my $cache = $self->{props}->{$property}->{cache};
         $callbacks->{on_set} and $callbacks->{on_set}->( $cache );
         $callbacks->{on_updated} and $callbacks->{on_updated}->( $cache );
         push @$cbs, $callbacks;
         $on_watched->() if $on_watched;
      }
      else {
         push @$cbs, $callbacks;
         $on_watched->() if $on_watched;
      }

      return;
   }

   $self->{props}->{$property}->{cbs} = [ $callbacks ];

   if( $smash ) {
      if( $want_initial ) {
         my $cache = $self->{props}->{$property}->{cache};
         $callbacks->{on_set} and $callbacks->{on_set}->( $cache );
         $callbacks->{on_updated} and $callbacks->{on_updated}->( $cache );
      }
      $on_watched->() if $on_watched;
      return;
   }

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_WATCH )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_bool( $want_initial ),

      on_response => sub {
         my ( $message ) = @_;
         my $type = $message->type;

         if( $type == MSG_WATCHING ) {
            $on_watched->() if $on_watched;
         }
         elsif( $type == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $type" );
         }
      },
   );
}

sub handle_request_UPDATE
{
   my $self = shift;
   my ( $message ) = @_;

   my $prop  = $message->unpack_str();
   my $how   = $message->unpack_typed( TYPE_U8 );

   my $pdef = $self->can_property( $prop ) or return;
   my $type = $pdef->{type};
   my $dim  = $pdef->{dim};

   my $p = $self->{props}->{$prop} ||= {};

   my $dimname = DIMNAMES->[$dim];
   if( my $code = $self->can( "_update_property_$dimname" ) ) {
      $code->( $self, $p, $type, $how, $message );
   }
   else {
      croak "Unrecognised property dimension $dim for $prop";
   }

   $_->{on_updated} and $_->{on_updated}->( $p->{cache} ) for @{ $p->{cbs} };
}

sub _update_property_scalar
{
   my $self = shift;
   my ( $p, $type, $how, $message ) = @_;

   if( $how == CHANGE_SET ) {
      my $value = $message->unpack_typed( $type );
      $p->{cache} = $value;
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   else {
      croak "Change type $how is not valid for a scalar property";
   }
}

sub _update_property_hash
{
   my $self = shift;
   my ( $p, $type, $how, $message ) = @_;

   if( $how == CHANGE_SET ) {
      my $value = $message->unpack_typed( Tangence::Meta::Type->new( dict => $type ) );
      $p->{cache} = $value;
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_ADD ) {
      my $key   = $message->unpack_str();
      my $value = $message->unpack_typed( $type );
      $p->{cache}->{$key} = $value;
      $_->{on_add} and $_->{on_add}->( $key, $value ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_DEL ) {
      my $key = $message->unpack_str();
      delete $p->{cache}->{$key};
      $_->{on_del} and $_->{on_del}->( $key ) for @{ $p->{cbs} };
   }
   else {
      croak "Change type $how is not valid for a hash property";
   }
}

sub _update_property_queue
{
   my $self = shift;
   my ( $p, $type, $how, $message ) = @_;

   if( $how == CHANGE_SET ) {
      my $value = $message->unpack_typed( Tangence::Meta::Type->new( list => $type ) );
      $p->{cache} = $value;
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_PUSH ) {
      my @value = $message->unpack_all_sametype( $type );
      push @{ $p->{cache} }, @value;
      $_->{on_push} and $_->{on_push}->( @value ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_SHIFT ) {
      my $count = $message->unpack_int();
      splice @{ $p->{cache} }, 0, $count, ();
      $_->{on_shift} and $_->{on_shift}->( $count ) for @{ $p->{cbs} };
   }
   else {
      croak "Change type $how is not valid for a queue property";
   }
}

sub _update_property_array
{
   my $self = shift;
   my ( $p, $type, $how, $message ) = @_;

   if( $how == CHANGE_SET ) {
      my $value = $message->unpack_typed( Tangence::Meta::Type->new( list => $type ) );
      $p->{cache} = $value;
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_PUSH ) {
      my @value = $message->unpack_all_sametype( $type );
      push @{ $p->{cache} }, @value;
      $_->{on_push} and $_->{on_push}->( @value ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_SHIFT ) {
      my $count = $message->unpack_int();
      splice @{ $p->{cache} }, 0, $count, ();
      $_->{on_shift} and $_->{on_shift}->( $count ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_SPLICE ) {
      my $start = $message->unpack_int();
      my $count = $message->unpack_int();
      my @value = $message->unpack_all_sametype( $type );
      splice @{ $p->{cache} }, $start, $count, @value;
      $_->{on_splice} and $_->{on_splice}->( $start, $count, @value ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_MOVE ) {
      my $index = $message->unpack_int();
      my $delta = $message->unpack_int();
      # it turns out that exchanging neighbours is quicker by list assignment,
      # but other times it's generally best to use splice() to extract then
      # insert
      if( abs($delta) == 1 ) {
         @{$p->{cache}}[$index,$index+$delta] = @{$p->{cache}}[$index+$delta,$index];
      }
      else {
         my $elem = splice @{ $p->{cache} }, $index, 1, ();
         splice @{ $p->{cache} }, $index + $delta, 0, ( $elem );
      }
      $_->{on_move} and $_->{on_move}->( $index, $delta ) for @{ $p->{cbs} };
   }
   else {
      croak "Change type $how is not valid for an array property";
   }
}

sub _update_property_objset
{
   my $self = shift;
   my ( $p, $type, $how, $message ) = @_;

   if( $how == CHANGE_SET ) {
      # Comes across in a LIST. We need to map id => obj
      my $objects = $message->unpack_typed( Tangence::Meta::Type->new( list => $type ) );
      $p->{cache} = { map { $_->id => $_ } @$objects };
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_ADD ) {
      # Comes as object only
      my $obj = $message->unpack_typed( $type );
      $p->{cache}->{$obj->id} = $obj;
      $_->{on_add} and $_->{on_add}->( $obj ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_DEL ) {
      # Comes as ID number only
      my $id = $message->unpack_int();
      delete $p->{cache}->{$id};
      $_->{on_del} and $_->{on_del}->( $id ) for @{ $p->{cbs} };
   }
   else {
      croak "Change type $how is not valid for an objset property";
   }
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
