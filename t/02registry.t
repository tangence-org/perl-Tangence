#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
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

my $mdef = $ball->can_method( "bounce" );
isa_ok( $mdef, "Tangence::Meta::Method", '$ball->can_method "bounce"' );
is( $mdef->name, "bounce", 'can_method "bounce" name' );
is_deeply( [ map $_->sig, $mdef->argtypes ], [qw( str )], 'can_method "bounce" argtypes' );
is( $mdef->ret->sig, "str", 'can_method "bounce" ret' );

ok( !$ball->can_method( "fly" ), '$ball->can_method "fly" is undef' );

my $methods = $ball->class->methods;
is_deeply( [ sort keys %$methods ],
           [qw( bounce )],
           '$ball->class->methods yields all' );

my $edef = $ball->can_event( "bounced" );
isa_ok( $edef, "Tangence::Meta::Event", '$ball->can_event "bounced"' );
is( $edef->name, "bounced", 'can_event "bounced" name' );
is_deeply( [ map $_->sig, $edef->argtypes ], [qw( str )], 'can_event "bounced" argtypes' );

ok( $ball->can_event( "destroy" ), '$ball->can_event "destroy"' );

ok( !$ball->can_event( "flew" ), '$ball->can_event "flew" is undef' );

my $events = $ball->class->events;
is_deeply( [ sort keys %$events ],
           [qw( bounced destroy )],
           '$ball->class->events yields all' );

my $pdef = $ball->can_property( "colour" );
isa_ok( $pdef, "Tangence::Meta::Property", '$ball->can_property "colour"' );
is( $pdef->name, "colour", 'can_property "colour" name' );
is( $pdef->dimension, DIM_SCALAR, 'can_property "colour" dimension' );
is( $pdef->type->sig, "str", 'can_property "colour" type' );

ok( !$ball->can_property( "style" ), '$ball->can_property "style" is undef' );

my $properties = $ball->class->properties;
is_deeply( [ sort keys %$properties ],
           [qw( colour size )],
           '$ball->class->properties yields all' );

is_deeply( $ball->smashkeys,
           [qw( size )],
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

done_testing;
