#!/usr/bin/perl -w

use strict;

use Test::More tests => 31;

use Tangence::Compiler::Parser;

use Tangence::Constants;

my $parser = Tangence::Compiler::Parser->new;

my $meta;

$meta = $parser->from_file( "t/Ball.tan" );
is_deeply( [ sort keys %$meta ], [sort qw( t.Colourable t.Ball )], 'keys of t/Ball.tan' );

my $methods;
my $events;
my $props;

my $colourable = $meta->{'t.Colourable'};
isa_ok( $colourable, "Tangence::Compiler::Class", 't.Colourable meta' );
is( $colourable->name, "t.Colourable", 't.Colourable name' );

$props = $colourable->properties;

isa_ok( $props->{colour}, "Tangence::Compiler::Property", 't.Colourable prop colour' );
is( $props->{colour}->name, "colour", 't.Colourable prop colour name' );
is( $props->{colour}->dimension, DIM_SCALAR, 't.Colourable prop colour dimension' );
is( $props->{colour}->type, "str", 't.Colourable prop colour type' );
ok( !$props->{colour}->smashed, 't.Colourable prop colour !smashed' );

my $ball = $meta->{'t.Ball'};
isa_ok( $ball, "Tangence::Compiler::Class", 't.Ball meta' );

$methods = $ball->methods;

isa_ok( $methods->{bounce}, "Tangence::Compiler::Method", 't.Ball method bounce' );
is( $methods->{bounce}->name, "bounce", 't.Ball method bounce name' );
is_deeply( [ $methods->{bounce}->args ], [qw( str )], 't.Ball method bounce args' );
is( $methods->{bounce}->ret,  "str", 't.Ball method bounce ret' );

$events = $ball->events;

isa_ok( $events->{bounced}, "Tangence::Compiler::Event", 't.Ball event bounced' );
is( $events->{bounced}->name, "bounced", 't.Ball event bounced name' );
is_deeply( [ $events->{bounced}->args ], [qw( str )], 't.Ball event bounced args' );

$props = $ball->properties;

is( $props->{size}->name, "size", 't.Ball prop size name' );
is( $props->{size}->dimension, DIM_SCALAR, 't.Ball prop size dimension' );
is( $props->{size}->type, "int", 't.Ball prop size type' );
ok( $props->{size}->smashed, 't.Ball prop size smashed' );

is_deeply( [ map { $_->name } $ball->supers ], [qw( t.Colourable )], 't.Ball meta supers' );

$meta = $parser->from_file( "t/TestObj.tan" );
my $testobj = $meta->{'t.TestObj'};

$props = $testobj->properties;

is( $props->{array}->dimension, DIM_ARRAY, 't.TestObj prop array dimension' );
is( $props->{array}->type, "int", 't.TestObj prop array type' );
is( $props->{hash}->dimension, DIM_HASH, 't.TestObj prop hash dimension' );
is( $props->{hash}->type, "int", 't.TestObj prop hash type' );
is( $props->{queue}->dimension, DIM_QUEUE, 't.TestObj prop queue dimension' );
is( $props->{queue}->type, "int", 't.TestObj prop queue type' );
is( $props->{scalar}->dimension, DIM_SCALAR, 't.TestObj prop scalar dimension' );
is( $props->{scalar}->type, "int", 't.TestObj prop scalar type' );
is( $props->{items}->dimension, DIM_SCALAR, 't.TestObj prop items dimension' );
is( $props->{items}->type, "list(obj)", 't.TestObj prop items type' );
