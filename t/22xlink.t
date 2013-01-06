#!/usr/bin/perl -w

use strict;

use Test::More tests => 24;
use Test::Fatal qw( dies_ok );
use Test::Refcount;

use Tangence::Constants;
use Tangence::Registry;

use Tangence::Server;
use Tangence::Client;

use t::TestObj;
use t::TestServerClient;

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

   dies_ok( sub { $objproxy->subscribe_event(
                    event => "no_such_event",
                    on_fire => sub {},
                  ); },
            'Subscribing to no_such_event fails in proxy' );
}

# Properties get/set
{
   is( $objproxy->prop( "s_scalar" ), 456, 'Smashed property initially set in proxy' );

   my $value;
   $objproxy->get_property(
      property => "scalar",
      on_value => sub { $value = shift },
   );

   is( $value, 123, '$value after get_property' );

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

   dies_ok( sub { $objproxy->get_property(
                    property => "no_such_property",
                    on_value => sub {},
                  ); },
            'Getting no_such_property fails in proxy' );
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
