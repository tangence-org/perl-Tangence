#!/usr/bin/perl -w

use strict;

use Test::More tests => 13;

use Tangence::Registry;
use t::Ball;

my $registry = Tangence::Registry->new();

ok( defined $registry, 'defined $registry' );
ok( $registry->isa( "Tangence::Registry" ), '$registry isa Tangence::Registry' );
ok( $registry->isa( "Tangence::Object"   ), '$registry isa Tangence::Object' );

is( $registry->id, "0", '$registry->id' );
is( $registry->describe, "Tangence::Registry", '$registry->describe' );

is_deeply( $registry->get_prop_objects, 
           { 0 => 'Tangence::Registry' },
           '$registry objects initially has only registry' );

my $added_object_id;
$registry->subscribe_event( "object_constructed", sub {
      my ( $obj, $event, @values ) = @_;
      $added_object_id = $values[0];
} );

my $ball = $registry->construct(
   "t::Ball",
   colour => "red"
);

ok( defined $ball, 'defined $ball' );
ok( $ball->isa( "t::Ball" ), '$ball isa t::Ball' );

is( $ball->id, "1", '$ball->id' );

is_deeply( $registry->get_prop_objects, 
           { 0 => 'Tangence::Registry',
             1 => 't::Ball[colour="red"]' },
           '$registry objects now has ball too' );

is( $added_object_id, "1", '$added_object_id is 1' );

ok( $registry->get_by_id( "1" ) == $ball, '$registry->get_by_id "1"' );

ok( !defined $registry->get_by_id( "2" ), '$registry->get_by_id "2"' );
