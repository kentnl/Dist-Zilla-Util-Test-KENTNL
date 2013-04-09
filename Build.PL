
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.4004"
  },
  "configure_requires" => {
    "Module::Build" => "0.4004"
  },
  "dist_abstract" => "KENTNL's DZil plugin testing tool.",
  "dist_author" => [
    "Kent Fredric <kentnl\@cpan.org>"
  ],
  "dist_name" => "Dist-Zilla-Util-Test-KENTNL",
  "dist_version" => "0.01015823",
  "license" => "perl",
  "module_name" => "Dist::Zilla::Util::Test::KENTNL",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Carp" => 0,
    "Dist::Zilla::Tester" => 0,
    "Sub::Exporter" => 0,
    "Test::DZil" => 0,
    "Try::Tiny" => 0,
    "perl" => "5.006",
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => [],
  "test_requires" => {
    "File::Find" => 0,
    "File::Temp" => 0,
    "Test::Fatal" => 0,
    "Test::More" => "0.98"
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
