use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new
  (
   module_name => 'Tangence',
   build_requires => {
                        'IO::Async' => 0.14,
                        'IO::Async::Test' => 0.14,
                        'Test::More' => 0,
                        'Test::Exception' => 0,
                     },
   license => 'perl',
   create_makefile_pl => 'traditional',
  );
  
$build->create_build_script;
