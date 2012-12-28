#!/usr/bin/perl -w

use strict;

use Test::More tests => 176;
use Test::Fatal qw( dies_ok );
use Test::HexString;

use Tangence::Message;
$Tangence::Message::SORT_HASH_KEYS = 1;

use Tangence::Meta::Type;
sub _make_type { Tangence::Meta::Type->new_from_sig( shift ) }

my $VERSION_MINOR = Tangence::Constants->VERSION_MINOR;

{
   # We need a testing stream that declares a version
   package TestStream;
   use base qw( Tangence::Stream );

   sub minor_version { $VERSION_MINOR }

   sub new { bless {}, shift }

   # Stub the methods we don't care about
   sub _install_watch { }
   sub make_proxy { }
   sub get_by_id { my ( $self, $id ) = @_; "OBJPROXY[id=$id]" }
}

Tangence::Struct->declare(
   "TestRecord",
   fields => [
      one => "int",
      two => "str",
   ],
);

sub test_specific
{
   my $name = shift;
   my %args = @_;

   my $m = Tangence::Message->new( TestStream->new );
   my $pack_method = "pack_$args{type}";
   is( $m->$pack_method( $args{data} ), $m, "$pack_method returns \$m for $name" );

   is_hexstr( $m->{record}, $args{stream}, "$pack_method $name" );

   my $unpack_method = "unpack_$args{type}";
   is_deeply( $m->$unpack_method(), exists $args{retdata} ? $args{retdata} : $args{data}, "$unpack_method $name" );
   is( length $m->{record}, 0, "eats all stream for $name" );
}

sub test_specific_dies
{
   my $name = shift;
   my %args = @_;

   dies_ok( sub {
      my $m = Tangence::Message->new( TestStream->new );
      my $pack_method = "pack_$args{type}";

      $m->$pack_method( $args{data} );
   }, "pack $name dies" ) if exists $args{data};

   dies_ok( sub {
      my $m = Tangence::Message->new( TestStream->new, undef, $args{stream} );
      my $unpack_method = "unpack_$args{type}";

      $m->$unpack_method()
   }, "unpack $name dies" ) if exists $args{stream};
}

use Tangence::Registry;
use t::Ball;

my $registry = Tangence::Registry->new(
   tanfile => "t/Ball.tan",
);

my $ball = $registry->construct(
   "t::Ball",
   colour => "red",
);
$ball->id == 1 or die "Expected ball->id to be 1";

test_specific "bool f",
   type   => "bool",
   data   => 0,
   stream => "\x00";

test_specific "bool t",
   type   => "bool",
   data   => 1,
   stream => "\x01";

# So many parts of code would provide undef == false, so we will serialise
# undef as false and not care about nullable
test_specific "bool undef",
   type   => "bool",
   data   => undef,
   stream => "\x00",
   retdata => 0;

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

test_specific_dies "int from undef",
   type   => "int",
   data   => undef,
   stream => "\x80";

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

test_specific_dies "string from undef",
   type   => "str",
   data   => undef,
   stream => "\x80";

test_specific "object",
   type   => "obj",
   data   => $ball,
             # DATAMETA_CLASS
   stream => "\xe2" . "\x27t::Ball" .
                      "\x02\1" .
                      "\x64" . "\x26events" . "\x62" . "\x27bounced" . "\x61" . "\x24args" . "\x41" . "\x23str" .
                                                       "\x27destroy" . "\x61" . "\x24args" . "\x40" .
                               "\x23isa" . "\x42" . "\x27t::Ball" .
                                                    "\x2dt::Colourable" .
                               "\x27methods" . "\x61" . "\x26bounce" . "\x62" . "\x24args" . "\x41" . "\x23str" .
                                                                                "\x23ret" . "\x23str" .
                               "\x2aproperties" . "\x62" . "\x26colour" . "\x62" . "\x23dim" . "\x211" .
                                                                                   "\x24type" . "\x23str" .
                                                           "\x24size" . "\x63" . "\x23dim" . "\x211" .
                                                                                 "\x25smash" . "\x211" .
                                                                                 "\x24type" . "\x23int" .
                      "\x41" . "\x24size" .
             # DATAMETA_CONSTRUCT
             "\xe1" . "\x02\1" .
                      "\x02\1" .
                      "\x41" . "\x80" .
             # DATA_OBJ
             "\x84" . "\0\0\0\1",
   retdata => "OBJPROXY[id=1]";

test_specific "record",
   type   => "record",
   data   => TestRecord->new( one => 1, two => 2 ),
             # DATAMETA_STRUCT
   stream => "\xe3" . "\x2aTestRecord" .
                      "\x02\1" .
                      "\x42" . "\x23one" . "\x23two" .
                      "\x42" . "\x23int" . "\x23str" .
             # DATA_RECORD
             "\xa2" . "\x02\1" .
                      "\x02\1" .
                      "\x212";

sub test_typed
{
   my $name = shift;
   my %args = @_;

   my $type = _make_type $args{sig};

   my $m = Tangence::Message->new( TestStream->new );
   is( $m->pack_typed( $type, $args{data} ), $m, "pack_typed returns \$m for $name" );

   is_hexstr( $m->{record}, $args{stream}, "pack_typed $name" );

   is_deeply( $m->unpack_typed( $type ), $args{data}, "unpack_typed $name" );
   is( length $m->{record}, 0, "eats all stream for $name" );
}

sub test_typed_dies
{
   my $name = shift;
   my %args = @_;

   my $sig = $args{sig};
   my $type = _make_type $sig;

   dies_ok( sub {
      my $m = Tangence::Message->new( TestStream->new );

      $m->pack_typed( $type, $args{data} );
   }, "pack_typed($sig) $name dies" ) if exists $args{data};

   dies_ok( sub {
      my $m = Tangence::Message->new( TestStream->new, undef, $args{stream} );

      $m->unpack_typed( $type )
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
   sig    => 'list(str)',
   data   => [ "a", "b", "c" ],
   stream => "\x43\x21a\x21b\x21c";

test_typed_dies "list(string) from string",
   sig    => 'list(str)',
   data   => "hello",
   stream => "\x25hello";

test_typed_dies "list(string) from ARRAY(ARRAY)",
   sig    => 'list(str)',
   data   => [ [] ],
   stream => "\x41\x40";

test_typed "dict(string)",
   sig    => 'dict(str)',
   data   => { one => "one", },
   stream => "\x61\x23one\x23one";

test_typed_dies "dict(string) from string",
   sig    => 'dict(str)',
   data   => "hello",
   stream => "\x25hello";

test_typed_dies "dict(string) from HASH(ARRAY)",
   sig    => 'dict(str)',
   data   => { splot => [] },
   stream => "\x61\x65splot\x40";

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
   stream => "\x61\x23key\x25value";

test_typed "any (HASH of string*2)",
   sig    => "any",
   data   => { a => "A", b => "B" },
   stream => "\x62\x21a\x{21}A\x21b\x{21}B";

test_typed "any (HASH of HASH)",
   sig    => "any",
   data   => { hash => {} },
   stream => "\x61\x24hash\x60";

test_typed "any (record)",
   sig    => "any",
   data   => TestRecord->new( one => 3, two => 4 ),
             # DATAMETA_STRUCT
   stream => "\xe3" . "\x2aTestRecord" .
                      "\x02\1" .
                      "\x42" . "\x23one" . "\x23two" .
                      "\x42" . "\x23int" . "\x23str" .
             # DATA_RECORD
             "\xa2" . "\x02\1" .
                      "\x02\3" .
                      "\x214";

my $m;

$m = Tangence::Message->new( 0 );
$m->pack_all_typed( [ map _make_type($_), 'int', 'str', 'bool' ], 10, "hello", "true" );

is_hexstr( $m->{record}, "\x02\x0a\x25hello\x01", 'pack_all_typed' );

is_deeply( [ $m->unpack_all_typed( [ map _make_type($_), 'int', 'str', 'bool' ] ) ], [ 10, "hello", 1 ], 'unpack_all_typed' );
is( length $m->{record}, 0, "eats all stream for all_typed" );

$m = Tangence::Message->new( 0 );
$m->pack_all_sametype( _make_type('int'), 10, 20, 30 );

is_hexstr( $m->{record}, "\x02\x0a\x02\x14\x02\x1e", 'pack_all_sametype' );

is_deeply( [ $m->unpack_all_sametype( _make_type('int') ) ], [ 10, 20, 30 ], 'unpack_all_sametype' );
is( length $m->{record}, 0, "eats all stream for all_sametype" );

$VERSION_MINOR = 1;
# records should no longer work

test_typed_dies "any from record on minor version 1",
   sig    => "any",
   data   => TestRecord->new( one => 5, two => 6 ),
             # DATAMETA_STRUCT
   stream => "\xe3" . "\x2aTestRecord" .
                      "\x02\1" .
                      "\x42" . "\x23one" . "\x23two" .
                      "\x42" . "\x23int" . "\x23str" .
             # DATA_RECORD
             "\xa2" . "\x02\1" .
                      "\x02\5" .
                      "\x216";
