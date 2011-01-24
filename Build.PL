use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tangence',
   requires => {
      'Encode' => 0,
      'IO::Async::Listener' => '0.36',
      'IO::Async::Loop' => '0.16',
      'IO::Async::Protocol::Stream' => 0,
      'IO::Async::Stream' => 0,
      'IO::Async::Test' => 0,
      'URI::Split' => 0,
   },
   build_requires => {
      'Test::Exception' => 0,
      'Test::HexString' => 0,
      'Test::Identity' => 0,
      'Test::Memory::Cycle' => 0,
      'Test::More' => 0,
      'Test::Refcount' => 0,
   },
   license => 'perl',
   create_makefile_pl => 'traditional',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
