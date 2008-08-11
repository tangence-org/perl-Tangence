#!/usr/bin/perl -w

use strict;

use Test::More tests => 39;
use Test::HexString;

use Tangence::Stream;
$Tangence::Stream::SORT_HASH_KEYS = 1;

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

   is_hexstr( $d, $args{stream}, "pack_data $name" );

   is_deeply( $s->unpack_data( $d ), $args{data}, "unpack_data $name" );
   is( length $d, 0, "eats all stream for $name" );
}

test_data "undef",
   data   => undef,
   stream => "\x80";

test_data "string",
   data   => "hello",
   stream => "\x25hello";

test_data "integer",
   data   => 100,
   stream => "\x{23}100";

test_data "ARRAY empty",
   data   => [],
   stream => "\x40";

test_data "ARRAY of string",
   data   => [qw( a b c )],
   stream => "\x43\x{21}a\x{21}b\x{21}c";

test_data "ARRAY of ARRAY",
   data   => [ [] ],
   stream => "\x41\x40";

test_data "HASH empty",
   data   => {},
   stream => "\x60";

test_data "HASH of string*1",
   data   => { key => "value" },
   stream => "\x61key\0\x25value";

test_data "HASH of string*2",
   data   => { a => "A", b => "B" },
   stream => "\x62a\0\x{21}Ab\0\x{21}B";

test_data "HASH of HASH",
   data   => { hash => {} },
   stream => "\x61hash\0\x60";
