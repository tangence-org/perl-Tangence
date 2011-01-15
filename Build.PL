use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tangence',
   requires => {
      'IO::Async'       => 0.17,
      'IO::Async::Test' => 0.14,
      'URI::Split' => 0,
   },
   build_requires => {
      'Test::Exception' => 0,
      'Test::HexString' => 0,
      'Test::Memory::Cycle' => 0,
      'Test::More' => 0,
      'Test::Refcount' => 0,
   },
   license => 'perl',
   create_makefile_pl => 'traditional',
);
  
$build->create_build_script;
