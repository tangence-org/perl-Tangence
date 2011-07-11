#!/usr/bin/perl -w

use strict;

use Test::More tests => 10; 

use Tangence::Compiler::Parser;

use Tangence::Constants;

my $parser = Tangence::Compiler::Parser->new;

my $meta;

$meta = $parser->from_file( "t/Ball.tan" );
is_deeply( [ sort keys %$meta ], [sort qw( t.Colourable t.Ball )], 'keys of t/Ball.tan' );

my $colourable = $meta->{'t.Colourable'};
isa_ok( $colourable, "Tangence::Compiler::Class", 't.Colourable meta' );
is( $colourable->name, "t.Colourable", 't.Colourable name' );
is_deeply( $colourable->props,
   {
      colour => { dim => DIM_SCALAR, type => 'str' },
   },
   't.Colourable meta props'
);

my $ball = $meta->{'t.Ball'};
isa_ok( $ball, "Tangence::Compiler::Class", 't.Ball meta' );
is_deeply( $ball->methods,
   {
      bounce => { args => [qw( str )], ret => 'str' },
   },
   't.Ball meta methods'
);
is_deeply( $ball->events,
   {
      bounced => { args => [qw( str )] },
   },
   't.Ball meta events'
);
is_deeply( $ball->props,
   {
      size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
   },
   't.Ball meta props'
);

is_deeply( [ $ball->supers ], [qw( t.Colourable )], 't.Ball meta supers' );

$meta = $parser->from_file( "t/TestObj.tan" );
my $testobj = $meta->{'t.TestObj'};
is_deeply( $testobj->props,
   {
      array  => { dim => DIM_ARRAY,  type => 'int' },
      hash   => { dim => DIM_HASH,   type => 'int' },
      queue  => { dim => DIM_QUEUE,  type => 'int' },
      scalar => { dim => DIM_SCALAR, type => 'int' },
      items  => { dim => DIM_SCALAR, type => 'list(obj)' },
   },
   't.TestObj meta props'
);
