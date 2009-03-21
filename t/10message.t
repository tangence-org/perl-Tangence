#!/usr/bin/perl -w

use strict;

use Test::More tests => 120;
use Test::HexString;

use Tangence::Message;
$Tangence::Message::SORT_HASH_KEYS = 1;

sub test_specific
{
   my $name = shift;
   my %args = @_;

   my $m = Tangence::Message->new( 0 );
   my $pack_method = "pack_$args{type}";
   is( $m->$pack_method( $args{data} ), $m, "$pack_method returns \$m for $name" );

   is_hexstr( $m->{record}, $args{stream}, "$pack_method $name" );

   my $unpack_method = "unpack_$args{type}";
   is_deeply( $m->$unpack_method(), $args{data}, "$unpack_method $name" );
   is( length $m->{record}, 0, "eats all stream for $name" );
}

test_specific "bool f",
   type   => "bool",
   data   => 0,
   stream => "\x00";

test_specific "bool t",
   type   => "bool",
   data   => 1,
   stream => "\x01";

test_specific "int tiny",
   type   => "int",
   data   => 20,
   stream => "\x02\x14";

test_specific "int -ve tiny",
   type   => "int",
   data   => -30,
   stream => "\x03\xe2";

test_specific "int",
   type   => "int",
   data   => 0x01234567,
   stream => "\x06\x01\x23\x45\x67";

test_specific "int -ve",
   type   => "int",
   data   => -0x07654321,
   stream => "\x07\xf8\x9a\xbc\xdf";

test_specific "string",
   type   => "str",
   data   => "hello",
   stream => "\x25hello";

test_specific "long string",
   type   => "str",
   data   => "ABC" x 20,
   stream => "\x3f\x3c" . ( "ABC" x 20 );

test_specific "marginal string",
   type   => "str",
   data   => "x" x 0x1f,
   stream => "\x3f\x1f" . ( "x" x 0x1f );

sub test_typed
{
   my $name = shift;
   my %args = @_;

   my $m = Tangence::Message->new( 0 );
   is( $m->pack_typed( $args{sig}, $args{data} ), $m, "pack_typed returns \$m for $name" );

   is_hexstr( $m->{record}, $args{stream}, "pack_typed $name" );

   is_deeply( $m->unpack_typed( $args{sig} ), $args{data}, "unpack_typed $name" );
   is( length $m->{record}, 0, "eats all stream for $name" );
}

test_typed "bool f",
   sig    => "bool",
   data   => 0,
   stream => "\x00";

test_typed "bool t",
   sig    => "bool",
   data   => 1,
   stream => "\x01";

test_typed "num u8",
   sig    => "u8",
   data   => 10,
   stream => "\x02\x0a";

test_typed "num s8",
   sig    => "s8",
   data   => 10,
   stream => "\x03\x0a";

test_typed "num s8 -ve",
   sig    => "s8",
   data   => -10,
   stream => "\x03\xf6";

test_typed "num s32",
   sig    => "s32",
   data   => 100,
   stream => "\x07\x00\x00\x00\x64";

test_typed "int tiny",
   sig    => "int",
   data   => 20,
   stream => "\x02\x14";

test_typed "int -ve tiny",
   sig    => "int",
   data   => -30,
   stream => "\x03\xe2";

test_typed "int",
   sig    => "int",
   data   => 0x01234567,
   stream => "\x06\x01\x23\x45\x67";

test_typed "int -ve",
   sig    => "int",
   data   => -0x07654321,
   stream => "\x07\xf8\x9a\xbc\xdf";

test_typed "string",
   sig    => "str",
   data   => "hello",
   stream => "\x25hello";

test_typed "any (undef)",
   sig    => "any",
   data   => undef,
   stream => "\x80";

test_typed "any (string)",
   sig    => "any",
   data   => "hello",
   stream => "\x25hello";

test_typed "any (ARRAY empty)",
   sig    => "any",
   data   => [],
   stream => "\x40";

test_typed "any (ARRAY of string)",
   sig    => "any",
   data   => [qw( a b c )],
   stream => "\x43\x{21}a\x{21}b\x{21}c";

test_typed "any (ARRAY of 0x25 undefs)",
   sig    => "any",
   data   => [ (undef) x 0x25 ],
   stream => "\x5f\x25" . ( "\x80" x 0x25 );

test_typed "any (ARRAY of ARRAY)",
   sig    => "any",
   data   => [ [] ],
   stream => "\x41\x40";

test_typed "any (HASH empty)",
   sig    => "any",
   data   => {},
   stream => "\x60";

test_typed "any (HASH of string*1)",
   sig    => "any",
   data   => { key => "value" },
   stream => "\x61key\0\x25value";

test_typed "any (HASH of string*2)",
   sig    => "any",
   data   => { a => "A", b => "B" },
   stream => "\x62a\0\x{21}Ab\0\x{21}B";

test_typed "any (HASH of HASH)",
   sig    => "any",
   data   => { hash => {} },
   stream => "\x61hash\0\x60";
