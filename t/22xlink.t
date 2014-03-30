#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Fatal qw( dies_ok );
use Test::Refcount;

use Tangence::Constants;
use Tangence::Registry;

use Tangence::Server;
use Tangence::Client;

use t::TestObj;
use t::TestServerClient;

use Tangence::Types;

my $registry = Tangence::Registry->new(
   tanfile => "t/TestObj.tan",
);
my $obj = $registry->construct(
   "t::TestObj",
   scalar   => 123,
   s_scalar => 456,
);

my ( $server, $client ) = make_serverclient( $registry );

my $objproxy = $client->rootobj;

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

   is( $result, "10/hello", 'result of call_method()' );

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

   is( $subbed, 1, '$subbed after subscribe_event' );

   $obj->fire_event( event => 20, "bye" );

   is( $event_i, 20, '$event_i after subscribed event' );

   $objproxy->unsubscribe_event(
      event => "event",
   );

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

   is( $value, 123, '$value after get_property' );

   $objproxy->get_property_element(
      property => "hash",
      key      => "two",
      on_value => sub { $value = shift },
   );

   is( $value, 2, '$value after get_property_element hash key' );

   $objproxy->get_property_element(
      property => "array",
      index    => 1,
      on_value => sub { $value = shift },
   );

   is( $value, 2, '$value after get_property_element array index' );

   my $didset = 0;
   $objproxy->set_property(
      property => "scalar",
      value    => 135,
      on_done  => sub { $didset = 1 },
   );

   is( $obj->get_prop_scalar, 135, '$obj->get_prop_scalar after set_property' );
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

   $obj->set_prop_scalar( 147 );

   is( $value, 147, '$value after watch_property/set_prop_scalar' );

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

   is( $secondvalue, 147, '$secondvalue after watch_property with want_initial' );

   $obj->set_prop_scalar( 159 );

   is( $value, 159, '$value after second set_prop_scalar' );
   is( $valuechanged, 1, '$valuechanged is true after second set_prop_scalar' );

   $objproxy->unwatch_property(
      property => "scalar",
   );

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

   ok( defined $iter, '$iter defined after MSG_WATCHING_ITER' );

   is( $first_idx, 0, '$first_idx after MSG_WATCHING_ITER' );
   is( $last_idx,  2, '$last_idx after MSG_WATCHING_ITER' );

   my $idx;
   my @more;
   $iter->next_forward(
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is( $idx, 0, 'next_forward starts at element 0' );
   is_deeply( \@more, [ 1 ], 'next_forward yielded 1 element' );

   undef @more;
   $iter->next_forward(
      count => 5,
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is( $idx, 1, 'next_forward starts at element 1' );
   is_deeply( \@more, [ 2, 3 ], 'next_forward yielded 2 elements' );

   undef @more;
   $iter->next_backward(
      on_more => sub { ( $idx, @more ) = @_ }
   );

   is( $idx, 2, 'next_backward starts at element 2' );
   is_deeply( \@more, [ 3 ], 'next_forward yielded 1 element' );

   undef $iter;
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
   $obj->set_prop_s_scalar( 468 );

   is( $value, 468, 'smashed prop update succeeds' );
}

# Test object destruction
{
   my $proxy_destroyed = 0;
   $objproxy->subscribe_event(
      event => "destroy",
      on_fire => sub { $proxy_destroyed = 1 },
   );

   my $obj_destroyed = 0;

   $obj->destroy( on_destroyed => sub { $obj_destroyed = 1 } );

   is( $proxy_destroyed, 1, 'proxy gets destroyed' );

   is( $obj_destroyed, 1, 'object gets destroyed' );
}

is_oneref( $client, '$client has refcount 1 before shutdown' );
is_oneref( $server, '$server has refcount 1 before shutdown' );
undef $client; undef $server;

is_oneref( $obj, '$obj has refcount 1 before shutdown' );
is_oneref( $objproxy, '$objproxy has refcount 1 before shutdown' );
is_oneref( $registry, '$registry has refcount 1 before shutdown' );

done_testing;
