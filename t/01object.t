#!/usr/bin/perl -w

use strict;

use Test::More tests => 21;

use Tangence::Constants;

use t::Ball;

# Here we'll cheat. Normally, the registry constructs all objects. But we
# haven't tested the registry yet, so we'll do it ourselves.

my $ball = t::Ball->new(
   id => 1,
   registry => "NOTYET", # Some true value. We know it isn't used in this test
   colour => "red",
);

ok( defined $ball, 'defined $ball' );
isa_ok( $ball, "Tangence::Object", '$ball isa Tangence::Object' );

is( $ball->id, "1", '$ball->id' );

is( $ball->describe, 't::Ball[colour="red"]', '$ball->describe' );

is_deeply( $ball->can_method( "bounce" ),
           { args => 'str', ret => '' }, '$ball->can_method "bounce"' );

is_deeply( $ball->can_method( "fly" ),
           undef, '$ball->can_method "fly" is undef' );

is_deeply( $ball->can_event( "bounced" ),
           { args => 'str' }, '$ball->can_event "bounced"' );

is_deeply( $ball->can_event( "destroy" ),
           { args => '' }, '$ball->can_event "destroy"' );

is_deeply( $ball->can_event( "flew" ),
           undef, '$ball->can_event "flew" is undef' );

is_deeply( $ball->can_property( "colour" ),
           { dim => DIM_SCALAR, type => 'int' }, '$ball->can_property "colour"' );

is_deeply( $ball->can_property( "style" ),
           undef, '$ball->can_property "style" is undef' );

is_deeply( $ball->introspect,
           {
              isa => [qw( t::Ball Tangence::Object )],
              methods => {
                 bounce     => { args => 'str',  ret => '' },
              },
              events => {
                 bounced => { args => 'str' },

                 destroy => { args => '' },
              },
              properties => {
                 colour => { dim => DIM_SCALAR, type => 'int' },
                 size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
              },
           }, '$ball introspect' );

is_deeply( $ball->smashkeys,
           { size => 1 },
           '$ball->smashkeys' );

my $bounces = 0;
my $howhigh;

my $id;

$id = $ball->subscribe_event( bounced => sub {
      my ( $obj, $event, @args ) = @_;
      $bounces++;
      $howhigh = $args[0];
} );

$ball->method_bounce( {}, "20 metres" );

is( $bounces, 1, '$bounces is 1 after ->bounce' );
is( $howhigh, "20 metres", '$howhigh is 20 metres' );

$ball->unsubscribe_event( bounced => $id );

$ball->method_bounce( {}, "10 metres" );

is( $bounces, 1, '$bounces is still 1 after unsubscribe ->bounce' );

is( $ball->get_prop_colour, "red", 'colour is initially red' );

my $colour;
$id = $ball->watch_property( colour => sub {
      my ( $obj, $prop, $how, @value ) = @_;
      $colour = $value[0];
} );

$ball->set_prop_colour( "blue" );

is( $ball->get_prop_colour, "blue", 'colour is now blue' );
is( $colour, "blue", '$colour is blue' );

$ball->unwatch_property( colour => $id );

$ball->set_prop_colour( "green" );

is( $ball->get_prop_colour, "green", 'colour is now green' );
is( $colour, "blue", '$colour is still blue' );
