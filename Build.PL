use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tangence',
   requires => {
      'Encode' => 0,
      'Exporter' => '5.57',
      'perl' => 5.010, # pack/unpack > specifiers
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
