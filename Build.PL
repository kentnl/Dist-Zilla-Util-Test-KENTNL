
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'English' => '0',
    'File::Find' => '0',
    'File::Temp' => '0',
    'Module::Build' => '0.3601',
    'Test::More' => '0.88'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'KENTNL\'s DZil plugin testing tool.',
  'dist_author' => [
    'Kent Fredric <kentnl@cpan.org>'
  ],
  'dist_name' => 'Dist-Zilla-Util-Test-KENTNL',
  'dist_version' => '0.01000004',
  'license' => 'perl',
  'module_name' => 'Dist::Zilla::Util::Test::KENTNL',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Carp' => '0',
    'Dist::Zilla::Tester' => '0',
    'Moose::Autobox' => '0',
    'Params::Util' => '0',
    'Sub::Exporter' => '0',
    'Try::Tiny' => '0'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
