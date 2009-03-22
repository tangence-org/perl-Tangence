#!/usr/bin/perl -w

use strict;

use Test::More tests => 25;

use Tangence::Constants;
use Tangence::Registry;
use t::TestObj;

my $registry = Tangence::Registry->new();
my $obj = $registry->construct(
   "t::TestObj",
);

my @event;

# SCALAR 

is( $obj->get_prop_scalar, "123", 'scalar initially' );

$obj->watch_property( 'scalar', sub { shift; @event = @_ } );

$obj->set_prop_scalar( "456" );
is( $obj->get_prop_scalar, "456", 'scalar after set' );
is_deeply( \@event, [ 'scalar', CHANGE_SET, "456" ], '@event after set' );

is_deeply( $obj->get_prop_hash, { one => 1, two => 2, three => 3 }, 'hash initially' );

# HASH

$obj->watch_property( 'hash', sub { shift; @event = @_ } );

$obj->set_prop_hash( { four => 4 } );
is_deeply( $obj->get_prop_hash, { four => 4 }, 'hash after set' );
is_deeply( \@event, [ 'hash', CHANGE_SET, { four => "4" } ], '@event after set' );

$obj->add_prop_hash( five => 5 );
is_deeply( $obj->get_prop_hash, { four => 4, five => 5 }, 'hash after add' );
is_deeply( \@event, [ 'hash', CHANGE_ADD, five => 5 ], '@event after add' );

$obj->add_prop_hash( five => 6 );
is_deeply( $obj->get_prop_hash, { four => 4, five => 6 }, 'hash after add as change' );
is_deeply( \@event, [ 'hash', CHANGE_ADD, five => 6 ], '@event after add as change' );

$obj->del_prop_hash( 'five' );
is_deeply( $obj->get_prop_hash, { four => 4 }, 'hash after del' );
is_deeply( \@event, [ 'hash', CHANGE_DEL, 'five' ], '@event after del' );

# ARRAY

is_deeply( $obj->get_prop_array, [ 1, 2, 3 ], 'array initially' );

$obj->watch_property( 'array', sub { shift; @event = @_ } );

$obj->set_prop_array( [ 4, 5, 6 ] );
is_deeply( $obj->get_prop_array, [ 4, 5, 6 ], 'array after set' );
is_deeply( \@event, [ 'array', CHANGE_SET, [ 4, 5, 6 ] ], '@event after set' );

$obj->push_prop_array( 7 );
is_deeply( $obj->get_prop_array, [ 4, 5, 6, 7 ], 'array after push' );
is_deeply( \@event, [ 'array', CHANGE_PUSH, 7 ], '@event after push' );

$obj->shift_prop_array;
is_deeply( $obj->get_prop_array, [ 5, 6, 7 ], 'array after shift' );
is_deeply( \@event, [ 'array', CHANGE_SHIFT, 1 ], '@event after shift' );

$obj->shift_prop_array( 2 );
is_deeply( $obj->get_prop_array, [ 7 ], 'array after shift(2)' );
is_deeply( \@event, [ 'array', CHANGE_SHIFT, 2 ], '@event after shift(2)' );

$obj->splice_prop_array( 0, 0, ( 5, 6 ) );
is_deeply( $obj->get_prop_array, [ 5, 6, 7 ], 'array after splice(0,0)' );
is_deeply( \@event, [ 'array', CHANGE_SPLICE, 0, 0, 5, 6 ], '@event after splice(0,0)' );

$obj->splice_prop_array( 2, 1, () );
is_deeply( $obj->get_prop_array, [ 5, 6 ], 'array after splice(2,1)' );
is_deeply( \@event, [ 'array', CHANGE_SPLICE, 2, 1 ], '@event after splice(2,1)' );
