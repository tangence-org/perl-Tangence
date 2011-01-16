#!/usr/bin/perl -w

use strict;

use Test::More tests => 46;
use Test::Identity;
use Test::Memory::Cycle;
use Test::Refcount;

use Tangence::Constants;

use Tangence::Registry;
use t::Ball;

my $registry = Tangence::Registry->new(
   tanfile => "t/Ball.tan",
);

ok( defined $registry, 'defined $registry' );
isa_ok( $registry, "Tangence::Registry", '$registry isa Tangence::Registry' );
isa_ok( $registry, "Tangence::Object"  , '$registry isa Tangence::Object' );

is( $registry->id, "0", '$registry->id' );
is( $registry->describe, "Tangence::Registry", '$registry->describe' );

is_deeply( $registry->get_prop_objects, 
           { 0 => 'Tangence::Registry' },
           '$registry objects initially has only registry' );

my $cb_self;
my $added_object_id;
$registry->subscribe_event(
   object_constructed => sub { ( $cb_self, $added_object_id ) = @_ }
);

my $ball = $registry->construct(
   "t::Ball",
   colour => "red"
);

ok( defined $ball, 'defined $ball' );
isa_ok( $ball, "t::Ball", '$ball isa t::Ball' );

is_oneref( $ball, '$ball has refcount 1 initially' );

is( $ball->id, "1", '$ball->id' );

is( $ball->registry, $registry, '$ball->registry' );

is_deeply( $registry->get_prop_objects, 
           { 0 => 'Tangence::Registry',
             1 => 't::Ball[colour="red"]' },
           '$registry objects now has ball too' );

identical( $cb_self, $registry, '$cb_self is $registry' );
is( $added_object_id, "1", '$added_object_id is 1' );

undef $cb_self;

ok( $registry->get_by_id( "1" ) == $ball, '$registry->get_by_id "1"' );

ok( !defined $registry->get_by_id( "2" ), '$registry->get_by_id "2"' );

is( $ball->describe, 't::Ball[colour="red"]', '$ball->describe' );

is_deeply( $ball->can_method( "bounce" ),
           { args => [qw( str )], ret => 'str' }, '$ball->can_method "bounce"' );

is_deeply( $ball->can_method( "fly" ),
           undef, '$ball->can_method "fly" is undef' );

is_deeply( $ball->can_method(),
           { 
              bounce => { args => [qw( str )], ret => 'str' },
           },
           '$ball->can_method() yields all' );

is_deeply( $ball->can_event( "bounced" ),
           { args => [qw( str )] }, '$ball->can_event "bounced"' );

is_deeply( $ball->can_event( "destroy" ),
           { args => [] }, '$ball->can_event "destroy"' );

is_deeply( $ball->can_event( "flew" ),
           undef, '$ball->can_event "flew" is undef' );

is_deeply( $ball->can_event(),
           {
              bounced => { args => [qw( str )] },
              destroy => { args => [] },
           },
           '$ball->can_event() yields all' );

is_deeply( $ball->can_property( "colour" ),
           { dim => DIM_SCALAR, type => 'str' }, '$ball->can_property "colour"' );

is_deeply( $ball->can_property( "style" ),
           undef, '$ball->can_property "style" is undef' );

is_deeply( $ball->can_property(),
           {
              colour => { dim => DIM_SCALAR, type => 'str' },
              size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
           },
           '$ball->can_property() yields all' );

is_deeply( $ball->introspect,
           {
              isa => [qw( t::Ball Tangence::Object t::Colourable )],
              methods => {
                 bounce => { args => [qw( str )], ret => 'str' },
              },
              events => {
                 bounced => { args => [qw( str )] },

                 destroy => { args => [] },
              },
              properties => {
                 colour => { dim => DIM_SCALAR, type => 'str' },
                 size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
              },
           }, '$ball introspect' );

is_deeply( $ball->smashkeys,
           { size => 1 },
           '$ball->smashkeys' );

my $bounces = 0;
undef $cb_self;
my $howhigh;

my $id;

$id = $ball->subscribe_event( bounced => sub {
      ( $cb_self, $howhigh ) = @_;
      $bounces++;
} );

is_oneref( $ball, '$ball has refcount 1 after subscribe_event' );

$ball->method_bounce( {}, "20 metres" );

is( $bounces, 1, '$bounces is 1 after ->bounce' );
identical( $cb_self, $ball, '$cb_self is $ball' );
is( $howhigh, "20 metres", '$howhigh is 20 metres' );

undef $cb_self;

$ball->unsubscribe_event( bounced => $id );

is_oneref( $ball, '$ball has refcount 1 after unsubscribe_event' );

$ball->method_bounce( {}, "10 metres" );

is( $bounces, 1, '$bounces is still 1 after unsubscribe ->bounce' );

is( $ball->get_prop_colour, "red", 'colour is initially red' );

my $colour;
$id = $ball->watch_property( colour => 
   on_set => sub { ( $cb_self, $colour ) = @_ },
);

is_oneref( $ball, '$ball has refcount 1 after watch_property' );

$ball->set_prop_colour( "blue" );

is( $ball->get_prop_colour, "blue", 'colour is now blue' );
identical( $cb_self, $ball, '$cb_self is $ball' );
is( $colour, "blue", '$colour is blue' );

undef $cb_self;

$ball->unwatch_property( colour => $id );

is_oneref( $ball, '$ball has refcount 1 after unwatch_property' );

$ball->set_prop_colour( "green" );

is( $ball->get_prop_colour, "green", 'colour is now green' );
is( $colour, "blue", '$colour is still blue' );

is_oneref( $ball, '$ball has refcount 1 just before unref' );

memory_cycle_ok( $ball, '$ball has no memory cycles' );

memory_cycle_ok( $registry, '$registry has no memory cycles' );
