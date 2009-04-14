#!/usr/bin/perl -w

use strict;

use Test::More tests => 154;
use Test::Exception;
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

sub test_specific_dies
{
   my $name = shift;
   my %args = @_;

   dies_ok( sub {
      my $m = Tangence::Message->new( 0 );
      my $pack_method = "pack_$args{type}";

      $m->$pack_method( $args{data} );
   }, "pack $name dies" ) if exists $args{data};

   dies_ok( sub {
      my $m = Tangence::Message->new( 0, undef, $args{stream} );
      my $unpack_method = "unpack_$args{type}";

      $m->$unpack_method()
   }, "unpack $name dies" ) if exists $args{stream};
}

test_specific "bool f",
   type   => "bool",
   data   => 0,
   stream => "\x00";

test_specific "bool t",
   type   => "bool",
   data   => 1,
   stream => "\x01";

test_specific_dies "bool from str",
   type   => "bool",
   stream => "\x20";

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

test_specific_dies "int from str",
   type   => "int",
   stream => "\x20";

test_specific_dies "int from ARRAY",
   type   => "int",
   data   => [],
   stream => "\x40";

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

test_specific_dies "string from ARRAY",
   type   => "str",
   data   => [],
   stream => "\x40";

sub test_typed
{
   my $name = shift;
   my %args = @_;

   my $sig = $args{sig};

   my $m = Tangence::Message->new( 0 );
   is( $m->pack_typed( $sig, $args{data} ), $m, "pack_typed returns \$m for $name" );

   is_hexstr( $m->{record}, $args{stream}, "pack_typed $name" );

   is_deeply( $m->unpack_typed( $sig ), $args{data}, "unpack_typed $name" );
   is( length $m->{record}, 0, "eats all stream for $name" );
}

sub test_typed_dies
{
   my $name = shift;
   my %args = @_;

   my $sig = $args{sig};

   dies_ok( sub {
      my $m = Tangence::Message->new( 0 );

      $m->pack_typed( $sig, $args{data} );
   }, "pack_typed($sig) $name dies" ) if exists $args{data};

   dies_ok( sub {
      my $m = Tangence::Message->new( 0, undef, $args{stream} );

      $m->unpack_typed( $sig )
   }, "unpack_typed($sig) $name dies" ) if exists $args{stream};
}

test_typed "bool f",
   sig    => "bool",
   data   => 0,
   stream => "\x00";

test_typed "bool t",
   sig    => "bool",
   data   => 1,
   stream => "\x01";

test_typed_dies "bool from str",
   sig    => "bool",
   stream => "\x20";

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

test_typed_dies "int from str",
   sig    => "int",
   stream => "\x20";

test_typed_dies "int from ARRAY",
   sig    => "int",
   data   => [],
   stream => "\x40";

test_typed "string",
   sig    => "str",
   data   => "hello",
   stream => "\x25hello";

test_typed_dies "string from ARRAY",
   sig    => "str",
   data   => [],
   stream => "\x40";

test_typed "list(string)",
   sig    => '[str',
   data   => [ "a", "b", "c" ],
   stream => "\x43\x21a\x21b\x21c";

test_typed_dies "list(string) from string",
   sig    => '[str',
   data   => "hello",
   stream => "\x25hello";

test_typed_dies "list(string) from ARRAY(ARRAY)",
   sig    => '[str',
   data   => [ [] ],
   stream => "\x41\x40";

test_typed "dict(string)",
   sig    => '{str',
   data   => { one => "one", },
   stream => "\x61one\0\x23one";

test_typed_dies "dict(string) from string",
   sig    => '{str',
   data   => "hello",
   stream => "\x25hello";

test_typed_dies "dict(string) from HASH(ARRAY)",
   sig    => '{str',
   data   => { splot => [] },
   stream => "\x61splot\0\x40";

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

my $m;

$m = Tangence::Message->new( 0 );
$m->pack_all_typed( [ 'int', 'str', 'bool' ], 10, "hello", "true" );

is_hexstr( $m->{record}, "\x02\x0a\x25hello\x01", 'pack_all_typed' );

is_deeply( [ $m->unpack_all_typed( [ 'int', 'str', 'bool' ] ) ], [ 10, "hello", 1 ], 'unpack_all_typed' );
is( length $m->{record}, 0, "eats all stream for all_typed" );

$m = Tangence::Message->new( 0 );
$m->pack_all_sametype( 'int', 10, 20, 30 );

is_hexstr( $m->{record}, "\x02\x0a\x02\x14\x02\x1e", 'pack_all_sametype' );

is_deeply( [ $m->unpack_all_sametype( 'int' ) ], [ 10, 20, 30 ], 'unpack_all_sametype' );
is( length $m->{record}, 0, "eats all stream for all_sametype" );
