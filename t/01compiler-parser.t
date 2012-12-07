#!/usr/bin/perl -w

use strict;

use Test::More tests => 51;
use Test::Identity;

use Tangence::Compiler::Parser;

use Tangence::Constants;

my $parser = Tangence::Compiler::Parser->new;

my $meta;

$meta = $parser->from_file( "t/Ball.tan" );
is_deeply( [ sort keys %$meta ], [sort qw( t.Colourable t.Ball )], 'keys of t/Ball.tan' );

my $methods;
my $events;
my $props;
my @args;

my $colourable = $meta->{'t.Colourable'};
isa_ok( $colourable, "Tangence::Meta::Class", 't.Colourable meta' );
is( $colourable->name, "t.Colourable", 't.Colourable name' );

$props = $colourable->direct_properties;

is_deeply( [ sort keys %$props ], [qw( colour )], 't.Colourable direct props' );

isa_ok( $props->{colour}, "Tangence::Meta::Property", 't.Colourable prop colour' );
is( $props->{colour}->name, "colour", 't.Colourable prop colour name' );
is( $props->{colour}->dimension, DIM_SCALAR, 't.Colourable prop colour dimension' );
is( $props->{colour}->type, "str", 't.Colourable prop colour type' );
ok( !$props->{colour}->smashed, 't.Colourable prop colour !smashed' );

is_deeply( [ sort keys %{ $colourable->properties } ], [qw( colour )], 't.Colourable props' );

my $ball = $meta->{'t.Ball'};
isa_ok( $ball, "Tangence::Meta::Class", 't.Ball meta' );

$methods = $ball->direct_methods;

is_deeply( [ sort keys %$methods ], [qw( bounce )], 't.Ball direct methods' );

isa_ok( $methods->{bounce}, "Tangence::Meta::Method", 't.Ball method bounce' );
identical( $methods->{bounce}->class, $ball, 't.Ball method bounce class' );
is( $methods->{bounce}->name, "bounce", 't.Ball method bounce name' );
@args = $methods->{bounce}->arguments;
is( scalar @args, 1, 't.Ball method bounce has 1 argument' );
is( $args[0]->name, "howhigh", 't.Ball method bounce arg[0] name' );
is( $args[0]->type, "str",     't.Ball method bounce arg[0] type' );
is_deeply( [ $methods->{bounce}->argtypes ], [qw( str )], 't.Ball method bounce argtypes' );
is( $methods->{bounce}->ret,  "str", 't.Ball method bounce ret' );

is_deeply( [ sort keys %{ $ball->methods } ], [qw( bounce )], 't.Ball methods' );

$events = $ball->direct_events;

is_deeply( [ sort keys %$events ], [qw( bounced )], 't.Ball direct events' );

isa_ok( $events->{bounced}, "Tangence::Meta::Event", 't.Ball event bounced' );
identical( $events->{bounced}->class, $ball, 't.Ball event bounced class' );
is( $events->{bounced}->name, "bounced", 't.Ball event bounced name' );
@args = $events->{bounced}->arguments;
is( scalar @args, 1, 't.Ball event bounced has 1 argument' );
is( $args[0]->name, "howhigh", 't.Ball event bounced arg[0] name' );
is( $args[0]->type, "str",     't.Ball event bounced arg[0] type' );
is_deeply( [ $events->{bounced}->argtypes ], [qw( str )], 't.Ball event bounced argtypes' );

is_deeply( [ sort keys %{ $ball->events } ], [qw( bounced )], 't.Ball events' );

$props = $ball->direct_properties;

is_deeply( [ sort keys %$props ], [qw( size )], 't.Ball direct props' );

identical( $props->{size}->class, $ball, 't.Ball prop size class' );
is( $props->{size}->name, "size", 't.Ball prop size name' );
is( $props->{size}->dimension, DIM_SCALAR, 't.Ball prop size dimension' );
is( $props->{size}->type, "int", 't.Ball prop size type' );
ok( $props->{size}->smashed, 't.Ball prop size smashed' );

is_deeply( [ sort keys %{ $ball->properties } ], [qw( colour size )], 't.Ball props' );

is_deeply( [ map { $_->name } $ball->direct_superclasses ], [qw( t.Colourable )], 't.Ball direct superclasses' );
is_deeply( [ map { $_->name } $ball->superclasses ], [qw( t.Colourable )], 't.Ball superclasses' );

$meta = $parser->from_file( "t/TestObj.tan" );
my $testobj = $meta->{'t.TestObj'};

$props = $testobj->direct_properties;

is( $props->{array}->dimension, DIM_ARRAY, 't.TestObj prop array dimension' );
is( $props->{array}->type, "int", 't.TestObj prop array type' );
is( $props->{hash}->dimension, DIM_HASH, 't.TestObj prop hash dimension' );
is( $props->{hash}->type, "int", 't.TestObj prop hash type' );
is( $props->{queue}->dimension, DIM_QUEUE, 't.TestObj prop queue dimension' );
is( $props->{queue}->type, "int", 't.TestObj prop queue type' );
is( $props->{scalar}->dimension, DIM_SCALAR, 't.TestObj prop scalar dimension' );
is( $props->{scalar}->type, "int", 't.TestObj prop scalar type' );
is( $props->{objset}->dimension, DIM_OBJSET, 't.TestObj prop objset dimension' );
is( $props->{objset}->type, "obj", 't.TestObj prop objset type' );
is( $props->{items}->dimension, DIM_SCALAR, 't.TestObj prop items dimension' );
is( $props->{items}->type, "list(obj)", 't.TestObj prop items type' );
