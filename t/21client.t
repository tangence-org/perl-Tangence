#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Fatal qw( dies_ok );
use Test::HexString;
use Test::Refcount;

use Tangence::Constants;

use t::Conversation;

use Tangence::Meta::Type;
use constant TYPE_INT => Tangence::Meta::Type->new( "int" );
use constant TYPE_STR => Tangence::Meta::Type->new( "str" );

$Tangence::Message::SORT_HASH_KEYS = 1;

my $client = TestClient->new();

# Initialisation
{
   is_hexstr( $client->recv_message, $C2S{INIT}, 'client stream initially contains MSG_INIT' );

   $client->send_message( $S2C{INITED} );

   is_hexstr( $client->recv_message, $C2S{GETROOT} . $C2S{GETREGISTRY}, 'client stream contains MSG_GETROOT and MSG_GETREGISTRY' );

   $client->send_message( $S2C{GETROOT} );
   $client->send_message( $S2C{GETREGISTRY} );
}

my $objproxy = $client->rootobj;

my $bagproxy;

# Methods
{
   my $mdef = $objproxy->can_method( "method" );

   ok( defined $mdef, 'defined $mdef' );
   is( $mdef->name, "method", '$mdef->name' );
   is_deeply( [ $mdef->argtypes ], [ TYPE_INT, TYPE_STR ], '$mdef->argtypes' );
   is( $mdef->ret, TYPE_STR, '$mdef->ret' );

   my $result;
   $objproxy->call_method(
      method => "method",
      args   => [ 10, "hello" ],
      on_result => sub { $result = shift },
   );

   is_hexstr( $client->recv_message, $C2S{CALL}, 'client stream contains MSG_CALL' );

   $client->send_message( $S2C{CALL} );

   is( $result, "10/hello", 'result of call_method()' );

   $objproxy->call_method(
      method => "noreturn",
      args   => [],
      on_result => sub {},
   );

   is_hexstr( $client->recv_message, $C2S{CALL_NORETURN}, 'client stream contains MSG_CALL for void-returning method' );

   $client->send_message( $S2C{CALL_NORETURN} );

   dies_ok( sub { $objproxy->call_method(
                    method => "no_such_method",
                    args   => [ 123 ],
                    on_result => sub {},
                  ); },
            'Calling no_such_method fails in proxy' );
}

# Events
{
   my $edef = $objproxy->can_event( "event" );

   ok( defined $edef, 'defined $edef' );
   is( $edef->name, "event", '$edef->event' );
   is_deeply( [ $edef->argtypes ], [ TYPE_INT, TYPE_STR ], '$edef->argtypes' );

   my $event_i;
   my $event_s;
   my $subbed;
   $objproxy->subscribe_event(
      event => "event",
      on_fire => sub {
         ( $event_i, $event_s ) = @_;
      },
      on_subscribed => sub { $subbed = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{SUBSCRIBE}, 'client stream contains MSG_SUBSCRIBE' );

   $client->send_message( $S2C{SUBSCRIBED} );

   is( $subbed, 1, '$subbed after MSG_SUBSCRIBED' );

   $client->send_message( $S2C{EVENT} );

   $client->recv_message; # MSG_OK

   is( $event_i, 20, '$event_i after subscribed event' );

   $objproxy->unsubscribe_event(
      event => "event",
   );

   is_hexstr( $client->recv_message, $C2S{UNSUBSCRIBE}, 'client stream contains MSG_UNSUBSCRIBE' );

   $client->send_message( $MSG_OK );

   dies_ok( sub { $objproxy->subscribe_event(
                    event => "no_such_event",
                    on_fire => sub {},
                  ); },
            'Subscribing to no_such_event fails in proxy' );
}

# Properties get/set
{
   my $pdef = $objproxy->can_property( "scalar" );

   ok( defined $pdef, 'defined $pdef' );
   is( $pdef->name, "scalar", '$pdef->name' );
   is( $pdef->dimension, DIM_SCALAR, '$pdef->dimension' );
   is( $pdef->type, TYPE_INT, '$pdef->type' );

   is( $objproxy->prop( "s_scalar" ), 456, 'Smashed property initially set in proxy' );

   my $value;
   $objproxy->get_property(
      property => "scalar",
      on_value => sub { $value = shift },
   );

   is_hexstr( $client->recv_message, $C2S{GETPROP}, 'client stream contains MSG_GETPROP' );

   $client->send_message( $S2C{GETPROP_123} );

   is( $value, 123, '$value after get_property' );

   $objproxy->get_property_element(
      property => "hash",
      key      => "two",
      on_value => sub { $value = shift },
   );

   is_hexstr( $client->recv_message, $C2S{GETPROPELEM_HASH}, 'client stream contains MSG_GETPROPELEM' );

   $client->send_message( $S2C{GETPROPELEM_HASH} );

   is( $value, 2, '$value after get_property_element hash key' );

   $objproxy->get_property_element(
      property => "array",
      index    => 1,
      on_value => sub { $value = shift },
   );

   is_hexstr( $client->recv_message, $C2S{GETPROPELEM_ARRAY}, 'client stream contains MSG_GETPROPELEM' );

   $client->send_message( $S2C{GETPROPELEM_ARRAY} );

   is( $value, 2, '$value after get_property_element array index' );

   my $didset = 0;
   $objproxy->set_property(
      property => "scalar",
      value    => 135,
      on_done  => sub { $didset = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{SETPROP}, 'client stream contains MSG_SETPROP' );

   $client->send_message( $MSG_OK );

   is( $didset, 1, '$didset after set_property' );
}

# Properties watch
{
   my $value;
   my $watched;
   $objproxy->watch_property(
      property => "scalar",
      on_set => sub { $value = shift },
      on_watched => sub { $watched = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{WATCH}, 'client stream contains MSG_WATCH' );

   $client->send_message( $S2C{WATCHING} );

   $client->send_message( $S2C{UPDATE_SCALAR_147} );

   is( $value, 147, '$value after watch_property/set_prop_scalar' );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

   my $valuechanged = 0;
   my $secondvalue;
   $objproxy->watch_property(
      property => "scalar",
      on_set => sub {
         $secondvalue = shift;
         $valuechanged = 1
      },
      want_initial => 1,
   );

   is_hexstr( $client->recv_message, $C2S{GETPROP}, 'client stream contains MSG_GETPROP' );

   $client->send_message( $S2C{GETPROP_147} );

   is( $secondvalue, 147, '$secondvalue after watch_property with want_initial' );

   $client->send_message( $S2C{UPDATE_SCALAR_159} );

   is( $value, 159, '$value after second MSG_UPDATE' );
   is( $valuechanged, 1, '$valuechanged is true after second MSG_UPDATE' );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK' );

   $objproxy->unwatch_property(
      property => "scalar",
   );

   is_hexstr( $client->recv_message, $C2S{UNWATCH}, 'client stream contains MSG_UNWATCH' );

   $client->send_message( $MSG_OK );

   dies_ok( sub { $objproxy->get_property(
                    property => "no_such_property",
                    on_value => sub {},
                  ); },
            'Getting no_such_property fails in proxy' );
}

# Property iterators
{
   my @value;
   my $iter;
   my ( $first_idx, $last_idx );
   my $watched;
   $objproxy->watch_property(
      property => "queue",
      on_set => sub { @value = @_ },
      on_push => sub { push @value, @_ },
      on_shift => sub { shift @value for 1 .. shift },
      iter_from => "first",
      on_iter => sub { ( $iter, $first_idx, $last_idx ) = @_ },
      on_watched => sub { $watched = 1 },
   );

   is_hexstr( $client->recv_message, $C2S{WATCH_ITER}, 'client stream contains MSG_WATCH_ITER' );

   $client->send_message( $S2C{WATCHING_ITER} );

   ok( defined $iter, '$iter defined after MSG_WATCHING_ITER' );

   is( $first_idx, 0, '$first_idx after MSG_WATCHING_ITER' );
   is( $last_idx,  2, '$last_idx after MSG_WATCHING_ITER' );

   my $idx;
   my @more;
   $iter->next_forward(
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is_hexstr( $client->recv_message, $C2S{ITER_NEXT_1}, 'client stream contains MSG_ITER_NEXT' );

   $client->send_message( $S2C{ITER_NEXT_1} );

   is( $idx, 0, 'next_forward starts at element 0' );
   is_deeply( \@more, [ 1 ], 'next_forward yielded 1 element' );

   undef @more;
   $iter->next_forward(
      count => 5,
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is_hexstr( $client->recv_message, $C2S{ITER_NEXT_5}, 'client stream contains MSG_ITER_NEXT' );

   $client->send_message( $S2C{ITER_NEXT_5} );

   is( $idx, 1, 'next_forward starts at element 1' );
   is_deeply( \@more, [ 2, 3 ], 'next_forward yielded 2 elements' );

   undef @more;
   $iter->next_backward(
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is_hexstr( $client->recv_message, $C2S{ITER_NEXT_BACK}, 'client stream contains MSG_ITER_NEXT' );

   $client->send_message( $S2C{ITER_NEXT_BACK} );

   is( $idx, 2, 'next_backward starts at element 2' );
   is_deeply( \@more, [ 3 ], 'next_forward yielded 1 element' );

   undef $iter;

   is_hexstr( $client->recv_message, $C2S{ITER_DESTROY}, 'client stream contains MSG_ITER_DESTROY' );

   $client->send_message( $MSG_OK );
}

# Smashed Properties
{
   my $value;
   my $watched;
   $objproxy->watch_property(
      property => "s_scalar",
      on_set => sub { $value = shift },
      on_watched => sub { $watched = 1 },
      want_initial => 1,
   );

   is( $watched, 1, 'watch_property on smashed prop is synchronous' );

   is( $value, 456, 'watch_property on smashed prop gives initial value' );

   undef $value;
   $client->send_message( $S2C{UPDATE_S_SCALAR_468} );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after smashed prop UPDATE' );

   is( $value, 468, 'smashed prop update succeeds' );
}

# Test object destruction
{
   my $proxy_destroyed = 0;
   $objproxy->subscribe_event(
      event => "destroy",
      on_fire => sub { $proxy_destroyed = 1 },
   );

   $client->send_message( $S2C{DESTROY} );

   is_hexstr( $client->recv_message, $MSG_OK, 'client stream contains MSG_OK after MSG_DESTROY' );

   is( $proxy_destroyed, 1, 'proxy gets destroyed' );
}

is_oneref( $client, '$client has refcount 1 before shutdown' );
undef $client;

is_oneref( $objproxy, '$objproxy has refcount 1 before shutdown' );

done_testing;

package TestClient;

use strict;
use base qw( Tangence::Client );

sub new
{
   my $self = bless { written => "" }, shift;
   $self->identity( "testscript" );
   $self->on_error( sub { die "Test failed early - $_[0]" } );
   $self->tangence_connected();
   return $self;
}

sub tangence_write
{
   my $self = shift;
   $self->{written} .= $_[0];
}

sub send_message
{
   my $self = shift;
   my ( $message ) = @_;
   $self->tangence_readfrom( $message );
   length($message) == 0 or die "Client failed to read the whole message";
}

sub recv_message
{
   my $self = shift;
   my $message = $self->{written};
   $self->{written} = "";
   return $message;
}
