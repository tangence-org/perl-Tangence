#!/usr/bin/perl -w

use strict;

use Test::More tests => 3; 

use Tangence::Compiler::Parser;

use Tangence::Constants;

my $meta;

$meta = Tangence::Compiler::Parser->from_file( "t/Ball.tan" );
is_deeply( $meta,
   {
      't.Colourable' => {
         props => {
            colour => { dim => DIM_SCALAR, type => 'str' },
         },
      },
      't.Ball' => {
         methods => {
            bounce => { args => [qw( str )], ret => 'str' },
         },
         events => {
            bounced => { args => [qw( str )] },
         },
         props => {
            size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
         },
         isa => [qw( t.Colourable )],
      },
   },
   'parsed t/Ball.tan'
);

$meta = Tangence::Compiler::Parser->from_file( "t/Bag.tan" );
is_deeply( $meta,
   {
      't.Colourable' => {
         props => {
            colour => { dim => DIM_SCALAR, type => 'str' },
         },
      },
      't.Ball' => {
         methods => {
            bounce => { args => [qw( str )], ret => 'str' },
         },
         events => {
            bounced => { args => [qw( str )] },
         },
         props => {
            size   => { dim => DIM_SCALAR, type => 'int', smash => 1 },
         },
         isa => [qw( t.Colourable )],
      },
      't.Bag' => {
         methods => {
            add_ball  => { args => [qw( obj )], ret => '' },
            get_ball  => { args => [qw( str )], ret => 'obj' },
            pull_ball => { args => [qw( str )], ret => 'obj' },
         },
         props => {
            colours => { dim => DIM_HASH, type => 'int' },
         },
      },
   },
   'parsed t/Bag.tan'
);

$meta = Tangence::Compiler::Parser->from_file( "t/TestObj.tan" );
is_deeply( $meta,
   {
      't.TestObj' => {
         props => {
            array  => { dim => DIM_ARRAY,  type => 'int' },
            hash   => { dim => DIM_HASH,   type => 'int' },
            queue  => { dim => DIM_QUEUE,  type => 'int' },
            scalar => { dim => DIM_SCALAR, type => 'int' },
         },
      },
   },
   'parsed t/TestObj.tan'
);
