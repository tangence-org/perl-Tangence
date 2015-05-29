#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010-2015 -- leonerd@leonerd.org.uk

package Tangence::ObjectProxy;

use strict;
use warnings;

our $VERSION = '0.20';

use Carp;

use Tangence::Constants;

use Tangence::Types;

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

      class => $args{class},

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

The following methods documented with a trailing call to C<< ->get >> return
L<Future> instances.

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

=head2 $classname = $proxy->classname

Returns the name of the class of the C<Tangence> object being proxied for.

=cut

sub classname
{
   my $self = shift;
   return $self->{class}->name;
}

=head2 $class = $proxyobj->class

Returns the L<Tangence::Meta::Class> object representing the class of this
object.

=cut

sub class
{
   my $self = shift;
   return $self->{class};
}

=head2 $method = $proxy->can_method( $name )

Returns the L<Tangence::Meta::Method> object representing the named method, or
C<undef> if no such method exists.

=cut

sub can_method
{
   my $self = shift;
   return $self->class->method( @_ );
}

=head2 $event = $proxy->can_event( $name )

Returns the L<Tangence::Meta::Event> object representing the named event, or
C<undef> if no such event exists.

=cut

sub can_event
{
   my $self = shift;
   return $self->class->event( @_ );
}

=head2 $property = $proxy->can_property( $name )

Returns the L<Tangence::Meta::Property> object representing the named
property, or C<undef> if no such property exists.

=cut

sub can_property
{
   my $self = shift;
   return $self->class->property( @_ );
}

# Don't want to call it "isa"
sub proxy_isa
{
   my $self = shift;
   if( @_ ) {
      my ( $class ) = @_;
      return !! grep { $_->name eq $class } $self->{class}, $self->{class}->superclasses;
   }
   else {
      return $self->{class}, $self->{class}->superclasses
   }
}

sub grab
{
   my $self = shift;
   my ( $smashdata ) = @_;

   foreach my $property ( keys %{ $smashdata } ) {
      my $value = $smashdata->{$property};
      my $dim = $self->can_property( $property )->dimension;

      if( $dim == DIM_OBJSET ) {
         # Comes across in a LIST. We need to map id => obj
         $value = { map { $_->id => $_ } @$value };
      }

      my $prop = $self->{props}->{$property} ||= {};
      $prop->{cache} = $value;
   }
}

=head2 $result = $proxy->call_method( $mname, @args )->get

Calls the given method on the server object, passing in the given arguments.
Returns a L<Future> that will yield the method's result.

=cut

sub call_method
{
   my $self = shift;
   my ( $method, @args ) = @_;

   # Detect void-context legacy uses
   defined wantarray or
      croak "->call_method in void context no longer useful - it now returns a Future";

   my $mdef = $self->can_method( $method )
      or croak "Class ".$self->classname." does not have a method $method";

   my $conn = $self->{conn};

   my $request = Tangence::Message->new( $conn, MSG_CALL )
         ->pack_int( $self->id )
         ->pack_str( $method );

   my @argtypes = $mdef->argtypes;
   $argtypes[$_]->pack_value( $request, $args[$_] ) for 0..$#argtypes;

   my $f = $conn->new_future;

   $conn->request(
      request => $request,

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_RESULT ) {
            my $result = $mdef->ret ? $mdef->ret->unpack_value( $message )
                                    : undef;
            $f->done( $result );
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $f->fail( $msg, tangence => );
         }
         else {
            $f->fail( "Unexpected response code $code", tangence => );
         }
      },
   );

   return $f;
}

=head2 $proxy->subscribe_event( %args )->get

Subscribes to the given event on the server object, installing a callback
function which will be invoked whenever the event is fired.

Takes the following named arguments:

=over 8

=item event => STRING

Name of the event

=item on_fire => CODE

Callback function to invoke whenever the event is fired

 $on_fire->( @args )

The returned C<Future> it is guaranteed to be completed before any invocation
of the C<on_fire> event handler.

=back

=cut

sub subscribe_event
{
   my $self = shift;
   my %args = @_;

   my $event = delete $args{event} or croak "Need a event";
   ref( my $callback = delete $args{on_fire} ) eq "CODE"
      or croak "Expected 'on_fire' as a CODE ref";

   $self->can_event( $event )
      or croak "Class ".$self->classname." does not have an event $event";

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      push @$cbs, $callback;
      return Future->done;
   }

   my @cbs = ( $callback );
   $self->{subscriptions}->{$event} = \@cbs;

   return Future->done if $event eq "destroy"; # This is automatically handled

   my $conn = $self->{conn};
   my $f = $conn->new_future;

   $conn->request(
      request => Tangence::Message->new( $conn, MSG_SUBSCRIBE )
         ->pack_int( $self->id )
         ->pack_str( $event ),

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_SUBSCRIBED ) {
            $f->done;
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $f->fail( $msg, tangence => );
         }
         else {
            $f->fail( "Unexpected response code $code", tangence => );
         }
      },
   );

   return $f;
}

sub handle_request_EVENT
{
   my $self = shift;
   my ( $message ) = @_;

   my $event = $message->unpack_str();
   my $edef = $self->can_event( $event ) or return;

   my @args = map { $_->unpack_value( $message ) } $edef->argtypes;

   if( my $cbs = $self->{subscriptions}->{$event} ) {
      foreach my $cb ( @$cbs ) { $cb->( @args ) }
   }
}

=head2 $proxy->unsubscribe_event( %args )

Removes an event subscription on the given event on the server object that was
previously installed using C<subscribe_event>.

Takes the following named arguments:

=over 8

=item event => STRING

Name of the event

=back

=cut

sub unsubscribe_event
{
   my $self = shift;
   my %args = @_;

   my $event = delete $args{event} or croak "Need a event";

   $self->can_event( $event )
      or croak "Class ".$self->classname." does not have an event $event";

   return if $event eq "destroy"; # This is automatically handled

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_UNSUBSCRIBE )
         ->pack_int( $self->id )
         ->pack_str( $event ),

      on_response => sub {},
   );
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

   my $pdef = $self->can_property( $property )
      or croak "Class ".$self->classname." does not have a property $property";

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_GETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property ),

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_RESULT ) {
            my $value = $pdef->overall_type->unpack_value( $message );
            $on_value->( $value );
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      },
   );
}

=head2 $proxy->get_property_element( %args )

Requests the current value of an element of the property from the server
object, and invokes a callback function when the value is received.

Takes the following named arguments

=over 8

=item property => STRING

The name of the property

=item index => INT

For queue or array dimension properties, the index of the element

=item key => STRING

For hash dimension properties, the key of the element

=item on_value => CODE

Callback function to invoke when the value is returned

 $on_value->( $value )

=item on_error => CODE

Optional. Callback function to invoke when an error is returned. The client's
default will apply if not provided.

 $on_error->( $error )

=back

=cut

sub get_property_element
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   ref( my $on_value = delete $args{on_value} ) eq "CODE" 
      or croak "Expected 'on_value' as a CODE ref";

   my $on_error = delete $args{on_error} || $self->{on_error};
   ref $on_error eq "CODE" or croak "Expected 'on_error' as a CODE ref";

   my $pdef = $self->can_property( $property )
      or croak "Class ".$self->classname." does not have a property $property";

   my $conn = $self->{conn};
   $conn->_ver_can_getpropelem or croak "Server is too old to support MSG_GETPROPELEM";

   my $request = Tangence::Message->new( $conn, MSG_GETPROPELEM )
      ->pack_int( $self->id )
      ->pack_str( $property );

   if( $pdef->dimension == DIM_HASH ) {
      defined $args{key} or croak "Need a key";
      $request->pack_str( $args{key} );
   }
   elsif( $pdef->dimension == DIM_ARRAY or $pdef->dimension == DIM_QUEUE ) {
      defined $args{index} or croak "Need an index";
      $request->pack_int( $args{index} );
   }
   else {
      croak "Cannot get_property_element of a non hash";
   }

   $conn->request(
      request => $request,

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_RESULT ) {
            my $value = $pdef->type->unpack_value( $message );
            $on_value->( $value );
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $code" );
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

   my $pdef = $self->can_property( $property )
      or croak "Class ".$self->classname." does not have a property $property";

   my $conn = $self->{conn};
   my $request = Tangence::Message->new( $conn, MSG_SETPROP )
         ->pack_int( $self->id )
         ->pack_str( $property );
   $pdef->type->pack_value( $request, $value ),

   $conn->request(
      request => $request,

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_OK ) {
            $on_done->() if $on_done;
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $code" );
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

=item iter_from => INT

Optional. If defined, requests that the server create an iterator for the
property value (whose dimension must be a queue). Its value indicates which
end of the queue the iterator should start from; C<ITER_FIRST> to start at
index 0, or C<ITER_LAST> to start at the highest-numbered index. The iterator
object will be returned to the C<on_iter> callback. The iterator is
constructed atomically with installing the watch.

This option is mutually-exclusive with C<want_initial>.

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

=item on_iter => CODE

Callback function to invoke when the iterator object is returned by the
server. This must be provided if C<iter_from> is provided. It is passed the
iterator object, and the first and last indices that the iterator will yield
(inclusive).

 $on_iter->( $iter, $first_idx, $last_idx )

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

   my $iter_from = delete $args{iter_from};
   if( !defined $iter_from ) {
      # ignore
   }
   elsif( $iter_from eq "first" ) {
      $iter_from = ITER_FIRST;
   }
   elsif( $iter_from eq "last" ) {
      $iter_from = ITER_LAST;
   }
   else {
      croak "Unrecognised 'iter_from' value %s";
   }

   my $on_iter;
   if( defined $iter_from ) {
      $on_iter = delete $args{on_iter};
      ref $on_iter eq "CODE" or croak "Expected 'on_iter' to be a CODE ref";
   }

   my $on_watched = $args{on_watched};

   my $pdef = $self->can_property( $property )
      or croak "Class ".$self->classname." does not have a property $property";

   my $callbacks = {};
   my $on_updated = delete $args{on_updated};
   if( $on_updated ) {
      ref $on_updated eq "CODE" or croak "Expected 'on_updated' to be a CODE ref";
      $callbacks->{on_updated} = $on_updated;
   }

   foreach my $name ( @{ CHANGETYPES->{$pdef->dimension} } ) {
      # All of these become optional if 'on_updated' is supplied
      next if $on_updated and not exists $args{$name};

      ref( $callbacks->{$name} = delete $args{$name} ) eq "CODE"
         or croak "Expected '$name' as a CODE ref";
   }

   # Smashed properties behave differently
   my $smash = $pdef->smashed;

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
   my $request;
   if( $iter_from ) {
      $conn->_ver_can_iter or croak "Server is too old to support MSG_WATCH_ITER";
      $pdef->dimension == DIM_QUEUE or croak "Can only iterate on queue-dimension properties";

      $request = Tangence::Message->new( $conn, MSG_WATCH_ITER )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_int( $iter_from );
   }
   else {
      $request = Tangence::Message->new( $conn, MSG_WATCH )
         ->pack_int( $self->id )
         ->pack_str( $property )
         ->pack_bool( $want_initial );
   }

   $conn->request(
      request => $request,

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_WATCHING ) {
            $on_watched->() if $on_watched;
         }
         elsif( $code == MSG_WATCHING_ITER ) {
            $on_watched->() if $on_watched;
            my $iter_id = $message->unpack_int();
            my $first_idx = $message->unpack_int();
            my $last_idx  = $message->unpack_int();

            my $iter = Tangence::ObjectProxy::_PropertyIterator->new( $self, $iter_id, $pdef->type );
            $on_iter->( $iter, $first_idx, $last_idx );
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      },
   );
}

sub handle_request_UPDATE
{
   my $self = shift;
   my ( $message ) = @_;

   my $prop  = $message->unpack_str();
   my $how   = TYPE_U8->unpack_value( $message );

   my $pdef = $self->can_property( $prop ) or return;
   my $type = $pdef->type;
   my $dim  = $pdef->dimension;

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
      my $value = $type->unpack_value( $message );
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
      my $value = Tangence::Type->new( dict => $type )->unpack_value( $message );
      $p->{cache} = $value;
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_ADD ) {
      my $key   = $message->unpack_str();
      my $value = $type->unpack_value( $message );
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
      my $value = Tangence::Type->new( list => $type )->unpack_value( $message );
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
      my $value = Tangence::Type->new( list => $type )->unpack_value( $message );
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
      my $objects = Tangence::Type->new( list => $type )->unpack_value( $message );
      $p->{cache} = { map { $_->id => $_ } @$objects };
      $_->{on_set} and $_->{on_set}->( $p->{cache} ) for @{ $p->{cbs} };
   }
   elsif( $how == CHANGE_ADD ) {
      # Comes as object only
      my $obj = $type->unpack_value( $message );
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

=head2 $proxy->unwatch_property( %args )

Removes a property watches on the given property on the server object that was
previously installed using C<watch_property>.

Takes the following named arguments:

=over 8

=item property => STRING

Name of the property

=back

=cut

sub unwatch_property
{
   my $self = shift;
   my %args = @_;

   my $property = delete $args{property} or croak "Need a property";

   $self->can_property( $property )
      or croak "Class ".$self->classname." does not have a property $property";

   # TODO: mark iterators as destroyed and invalid
   delete $self->{props}->{$property};

   my $conn = $self->{conn};
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_UNWATCH )
         ->pack_int( $self->id )
         ->pack_str( $property ),

      on_response => sub {},
   );
}

package # hide from index
   Tangence::ObjectProxy::_PropertyIterator;
use Carp;
use Tangence::Constants;

=head1 ITERATOR METHODS

The following methods are availilable on the property iterator objects given
to the C<on_iter> callback of a C<watch_property> method.

=cut

sub new
{
   my $class = shift;
   return bless [ @_ ], $class;
}

sub obj { shift->[0] }
sub id  { shift->[1] }
sub conn { shift->obj->{conn} }

sub DESTROY
{
   my $self = shift;

   return unless $self->obj and my $id = $self->id and my $conn = $self->conn;

   $conn->request(
      request => Tangence::Message->new( $conn, MSG_ITER_DESTROY )
         ->pack_int( $id ),

      on_response => sub {},
   );
}

=head2 $iter->next_forward( %args )

=head2 $iter->next_backward( %args )

Requests the next items from the iterator. C<next_forward> moves forwards
towards higher-numbered indices, and C<next_backward> moves backwards towards
lower-numbered indices.

The following arguments are recognised:

=over 8

=item count => INT

Optional. Gives the number of elements requested. Will default to 1 if not
provided.

=item on_more => CODE

Callback to invoke when the new elements are returned. This will be invoked
with the index of the first element returned, and the new elements. Note that
there may be fewer elements returned than were requested, if the end of the
queue was reached. Specifically, there will be no new elements if the iterator
is already at the end.

 $on_more->( $index, @items )

=back

=cut

sub next_forward
{
   my $self = shift;
   $self->_next( direction => ITER_FWD, @_ );
}

sub next_backward
{
   my $self = shift;
   $self->_next( direction => ITER_BACK, @_ );
}

sub _next
{
   my $self = shift;
   my %args = @_;

   my $obj = $self->obj;
   my $id  = $self->id;
   my $element_type = $self->[2];

   my $on_more  = $args{on_more} or croak "Expected 'on_more' as a CODE ref";
   my $on_error = $args{on_error} || $obj->{on_error};

   my $conn = $self->conn;
   $conn->request(
      request => Tangence::Message->new( $conn, MSG_ITER_NEXT )
         ->pack_int( $id )
         ->pack_int( $args{direction} )
         ->pack_int( $args{count} || 1 ),

      on_response => sub {
         my ( $message ) = @_;
         my $code = $message->code;

         if( $code == MSG_ITER_RESULT ) {
            $on_more->(
               $message->unpack_int(),
               $message->unpack_all_sametype( $element_type ),
            );
         }
         elsif( $code == MSG_ERROR ) {
            my $msg = $message->unpack_str();
            $on_error->( $msg );
         }
         else {
            $on_error->( "Unexpected response code $code" );
         }
      }
   );
}

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
