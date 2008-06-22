#!/usr/bin/perl -w

use strict;

use Test::More tests => 39;

use Tangence::Stream;

my $d;

is( $d = Tangence::Stream::pack_num(      0 ),               "\0", 'pack_num 0' );
is( Tangence::Stream::unpack_num( $d ), 0, 'unpack_num 0' );
is( length $d, 0, 'eats all string' );

is( $d = Tangence::Stream::pack_num(      1 ),               "\1", 'pack_num 1' );
is( Tangence::Stream::unpack_num( $d ), 1, 'unpack_num 1' );
is( length $d, 0, 'eats all string' );

is( $d = Tangence::Stream::pack_num( 0x1000 ), "\x80\x00\x10\x00", 'pack_num 0x1000' );
is( Tangence::Stream::unpack_num( $d ), 0x1000, 'unpack_num 0x1000' );
is( length $d, 0, 'eats all string' );

# We're just testing the simple pack and unpack methods here, so no object
# will actually be needed
my $s = "Tangence::Stream";

sub test_data
{
   my $name = shift;
   my %args = @_;

   # Test round-trip of data to stream and back again

   $d = $s->pack_data( $args{data} );

   if( exists $args{stream} ) {
      is( $d, $args{stream}, "pack_data $name" );
   }
   else {
      ok( defined $d && !ref $d && length $d, "pack_data $name gives non-empty string" );
   }

   is_deeply( $s->unpack_data( $d ), $args{data}, "unpack_data $name" );
   is( length $d, 0, "eats all stream for $name" );
}

test_data "undef",
   data   => undef,
   stream => "\0";

test_data "string",
   data   => "hello",
   stream => "\1\x05hello";

test_data "integer",
   data   => 100,
   stream => "\1\x{03}100";

test_data "ARRAY empty",
   data   => [],
   stream => "\2\0";

test_data "ARRAY of string",
   data   => [qw( a b c )],
   stream => "\2\3\1\x{01}a\1\x{01}b\1\x{01}c";

test_data "ARRAY of ARRAY",
   data   => [ [] ],
   stream => "\2\1\2\0";

test_data "HASH empty",
   data   => {},
   stream => "\3\0";

test_data "HASH of string*1",
   data   => { key => "value" },
   stream => "\3\1key\0\1\5value";

test_data "HASH of string*2",
   data   => { a => "A", b => "B" };
   # Can't predict stream as we don't know the order

test_data "HASH of HASH",
   data   => { hash => {} },
   stream => "\3\1hash\0\3\0";
