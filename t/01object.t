#!/usr/bin/perl -w

use strict;

use Test::More tests => 34;
use Test::Identity;
use Test::Memory::Cycle;
use Test::Refcount;

use Tangence::Constants;

use t::Ball;

# Here we'll cheat. Normally, the registry constructs all objects. But we
# haven't tested the registry yet, so we'll do it ourselves.

my $fakereg = bless [], "FakeRegistry";
my $fakereg_got_destroy = 0;

sub FakeRegistry::destroy_object { shift; $fakereg_got_destroy = shift->id; }
sub FakeRegistry::get_meta_class { shift; Tangence::Meta::Class->new( shift ) }

my $ball = t::Ball->new(
   id => 1,
   registry => $fakereg,
   colour => "red",
);

ok( defined $ball, 'defined $ball' );
isa_ok( $ball, "Tangence::Object", '$ball isa Tangence::Object' );

is_oneref( $ball, '$ball has refcount 1 initially' );

is( $ball->id, "1", '$ball->id' );

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
my $cb_self;
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

$ball->destroy;
undef $ball;

is( $fakereg_got_destroy, 1, 'registry acknowledges object destruction' );
