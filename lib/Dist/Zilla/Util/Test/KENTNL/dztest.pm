use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Util::Test::KENTNL::dztest;

our $VERSION = '1.004003';

# ABSTRACT: Shared dist testing logic for easy dzil things

# AUTHORITY

use Carp qw( croak );
use Moose qw( has );
use Test::DZil qw( Builder );
use Test::Fatal qw( exception );
use Test::More 0.96 qw( );    # subtest
use Path::Tiny qw(path);
use Dist::Zilla::Util;
use Dist::Zilla::App::Tester qw( test_dzil );
use Module::Runtime qw();

## no critic (ValuesAndExpressions::ProhibitConstantPragma,ErrorHandling::RequireCheckingReturnValueOfEval,Subroutines::ProhibitSubroutinePrototypes)
use constant CAN_DPATH    => eval { require Data::DPath;       1 };
use constant CAN_EQORDIFF => eval { require Test::Differences; 1 };
sub dpath($);
BEGIN { CAN_DPATH and Data::DPath->import('dpath') }
## use critic

=method C<add_file>

Add a file to the scratch directory to be built.

  # ->add_file( $path, $string );
  # ->add_file( \@path, $string );
  $test->add_file('dist.ini', simple_ini() );
  $test->add_file('lib/Foo.pm', $content );
  $test->add_file([ 'lib','Foo.pm' ], $content );

=cut

sub add_file {
  my ( $self, $path, $content ) = @_;
  my $target = $self->tempdir->child( _file_list($path) );
  $target->parent->mkpath;
  $target->spew_raw($content);
  $self->files->{ $target->relative( $self->tempdir ) } = $target;
  return;
}

=method C<build_ok>

Build the dist safely, and report C<ok> if the dist builds C<ok>, spewing file listings via C<note>

C<BAIL_OUT> is triggered if any of C<add_file> don't arrive in the intended location.

=cut

sub _subtest_build_ok {
  my ($self) = @_;

  for my $file ( values %{ $self->files } ) {
    next if -e $file and not -d $file;
    return $self->tb->BAIL_OUT("expected file $file failed to add to tempdir");
  }
  $self->note_tempdir_files;

  my $exception;
  $self->tb->is_eq( $exception = $self->safe_configure, undef, 'Can load config' );
  $self->tb->diag($exception) if $exception;

  $self->tb->is_eq( $exception = $self->safe_build, undef, 'Can build' );
  $self->tb->diag($exception) if $exception;

  $self->note_builddir_files;
  return;
}

sub build_ok {
  my ($self) = @_;
  return $self->tb->subtest(
    'Configure and build' => sub {
      $self->tb->plan( tests => 2 );
      return $self->_subtest_build_ok;
    },
  );
}

=method C<prereqs_deeply>

Demand C<distmeta> C<prereqs> exactly match those specified.

  $test->prereqs_deeply( { hash } );

This is just a more memorable version of

  $test->meta_path_deeply('/prereqs/', { });

=cut

sub _subtest_prereqs_deeply {
  my ( $self, $prereqs ) = @_;
  my $meta = $self->distmeta;
  $self->tb->ok( defined $meta, 'distmeta defined' );
  $self->tb->note( $self->tb->explain( $meta->{prereqs} ) );

  if (CAN_EQORDIFF) {
    Test::Differences::eq_or_diff( $meta->{prereqs}, $prereqs, 'Prereqs match expected set' );
  }
  else {
    Test::More::is_deeply( $meta->{prereqs}, $prereqs, 'Prereqs match expected set' );
  }
  return;
}

sub prereqs_deeply {
  my ( $self, $prereqs ) = @_;
  return $self->tb->subtest(
    'distmeta prereqs comparison' => sub {
      $self->tb->plan( tests => 2 );
      $self->_subtest_prereqs_deeply($prereqs);
    },
  );
}

=method C<has_messages>

Test that there are messages, and all the given rules match messages.

  $test->has_messages( 'Some descriptor', [
     [ $regex, $description ],
     [ $regex, $description ],
  ]);

=cut

sub _test_has_message {
  my ( $self, $log, $regex, $reason ) = @_;
  my $i = 0;
  for my $item ( @{$log} ) {
    if ( $item =~ $regex ) {
      $self->tb->note( qq[item $i: ], $self->tb->explain($item) );
      $self->tb->ok( 1, "log message $i matched $regex$reason" );
      return 1;
    }
    $i++;
  }
  $self->tb->ok( undef, "No log messages matched $regex$reason" );
  return;
}

sub _subtest_has_messages {
  my ( $self, $map ) = @_;
  my $log = $self->builder->log_messages;
  $self->tb->ok( scalar @{$log}, ' has messages' );
  my $need_diag;
  for my $entry ( @{$map} ) {
    my ( $regex, $reason ) = @{$entry};
    $reason = ": $reason" if $reason;
    $reason = q[] unless $reason;
    $need_diag = 1 unless $self->_test_has_message( $log, $regex, $reason );
  }
  if ($need_diag) {
    $self->tb->diag( $self->tb->explain($log) );
    return;
  }
  return 1;
}

sub has_messages {
  my $nargs = ( my ( $self, $label, $map ) = @_ );

  croak 'Invalid number of arguments ( < 2 )' if 1 == $nargs;
  croak 'Invalid number of arguments ( > 3 )' if $nargs > 3;

  if ( 2 == $nargs ) {
    $map   = $label;
    $label = 'log messages check';
  }
  return $self->tb->subtest(
    $label => sub {
      $self->tb->plan( tests => 1 + scalar @{$map} );
      $self->_subtest_has_messages($map);
    },
  );
}

=method C<meta_path_deeply>

  $test->meta_path_deeply( $expression, $expected_data, $reason );

Uses C<$expression> as a L<< C<Data::DPath>|Data::DPath >> expression to pick a I<LIST> of nodes
from C<distmeta>, and compare that I<LIST> vs C<$expected_data>

  # Matches only the first author.
  $test->meta_path_deeply('/author/*/[1]', ['SomeAuthorName <wadef@wath>'], $reason );

  # Matches all authors
  $test->meta_path_deeply('/author/*/*', ['SomeAuthorName <wadef@wath>','Author2', ..], $reason );

=cut

sub _subtest_meta_path_deeply {
  my ( $self, $expression, $expected ) = @_;
  if ( not 'ARRAY' eq ref $expected ) {
    $self->tb->diag(<<'EOF');
WARNING: Author appears to have forgotten to wrap $expected with [], and this may cause a bug.
EOF
    $expected = [$expected];
  }
  my (@results) = dpath($expression)->match( $self->builder->distmeta );
  $self->tb->ok( @results > 0, "distmeta matched expression $expression" );
  $self->tb->note( $self->tb->explain( \@results ) );
  if (CAN_EQORDIFF) {
    Test::Differences::eq_or_diff( \@results, $expected, 'distmeta matched expectations' );
  }
  else {
    Test::More::is_deeply( \@results, $expected, 'distmeta matched expectations' );
  }
  return;
}

sub _todo_meta_path_deeply {
  my ( $self, $expression ) = @_;
  if ( not $self->{diaged} ) {
    $self->{diaged} = 1;
    $self->tb->diag('Data::DPath needed to accurately perform some of this test');
  }
  $self->tb->todo_skip("distmeta matched expression $expression needs Data::DPath");
  $self->tb->todo_skip('distmeta matched expectations needs Data::DPath');
  return;
}

sub meta_path_deeply {
  my ( $self, $expression, $expected, $reason ) = @_;
  if ( not $reason ) {
    $reason = "distmeta at $expression matches expected";
  }
  return $self->tb->subtest(
    $reason => sub {
      $self->tb->plan( tests => 2 );
      if (CAN_DPATH) {
        return $self->_subtest_meta_path_deeply( $expression, $expected );
      }
      return $self->_todo_meta_path_deeply($expression);
    },
  );
}

=method C<test_has_built_file>

Test ( as in, C<Test::More::ok> ) that a file exists in the C<dzil> build output directory.

Also returns it if it exists.

  $test->test_has_built_file('dist.ini');  # ok/fail

  my $object = test->test_has_built_file('dist.ini'); # ok/fail + return

=cut

sub test_has_built_file {
  my ( $self, $path ) = @_;
  if ( not -e $self->_build_root or not -d $self->_build_root ) {
    $self->tb->ok( undef, 'build root does not exist, cant have files' );
    return;
  }
  my $file = $self->_build_root->child( _file_list($path) );
  if ( defined $file and -e $file and not -d $file ) {
    $self->tb->ok( 1, "$file exists" );
    return $file;
  }
  $self->tb->ok( undef, "$file exists" );
  return;
}

=method C<create_plugin>

Create an instance of the named plugin and return it.

  my $t = dztest();
  $t->add_file('dist.ini', simple_ini( ... ));
  my $plugin = $t->create_plugin('GatherDir' => { ignore_dotfiles => 1 });
  # poke at $plugin here

Note: This lets you test plugins outside the requirement of inter-operating
with C<dzil> phases, but has the downside of not interacting with C<dzil> phases,
or even being I<*seen*> by C<dzil> phases.

But this is OK if you want to directly test a modules interface instead of doing
it through the proxy of C<dzil>

You can also subsequently create many such objects without requiring a C<dzil build> penalty.

=cut

sub create_plugin {
  my $nargs = ( my ( $self, $package, $name, $args ) = @_ );
  if ( 2 == $nargs ) {
    $name = $package;
    $args = {};
  }
  if ( 3 == $nargs ) {
    if ( ref $name ) {
      $args = $name;
      $name = $package;
    }
    else {
      $args = {};
    }
  }
  my $expanded = Dist::Zilla::Util->expand_config_package_name($package);
  Module::Runtime::require_module($expanded);
  return $expanded->new(
    zilla       => $self->configure,
    plugin_name => $name,
    %{$args},
  );
}

has tb => (
  is      => ro =>,
  lazy    => 1,
  default => sub {
    Test::More->builder;
  },
);
has files => (
  is   => ro =>,
  lazy => 1,
  default => sub { return {}; },
);

has tempdir => (
  is         => ro =>,
  lazy_build => 1,
);

sub _build_tempdir {
  my ($self) = @_;
  my $tempdir = Path::Tiny->tempdir;
  $self->tb->note("Creating fake dist in $tempdir");
  return $tempdir;
}

sub _file_list {
  my ($file) = @_;
  if ( 'ARRAY' eq ref $file ) {
    return @{$file};
  }
  return ($file);
}

=method C<source_file>

Re-fetch content added with C<add_file>.

You probably want C<built_file>.

  $test->source_file( $path  );
  $test->source_file( \@path );

Returns C<undef> if the file does not exist.

  if ( my $content = $test->source_file('dist.ini') ) {
    print $content->slurp_raw;
  }

=cut

sub source_file {
  my ( $self, $path ) = @_;
  my $file = $self->tempdir->child( _file_list($path) );
  return unless -e $file;
  return if -d $file;
  return $file;
}

has builder => (
  is         => ro =>,
  lazy_build => 1,
  handles    => {
    distmeta => 'distmeta',
  },
);
sub build { my ($self) = @_; return $self->builder }

sub _build_builder {
  my ($self) = @_;
  my $b = $self->configure;
  $b->build;
  return $b;
}

=method C<safe_build>

Ensure the distribution is built safely, returns exceptions or C<undef>.

  if ( $test->safe_build ) {
    say "Failed build";
  }

=cut

sub safe_build {
  my ($self) = @_;
  return exception { $self->build };
}

=attr C<configure>

Construct the internal builder object.

  $test->configure;

=cut

has configure => (
  is         => ro =>,
  lazy_build => 1,
);

sub _build_configure {
  my ($self) = @_;
  my $b = Builder->from_config( { dist_root => q[] . $self->tempdir } );
  return $b;
}

=method C<safe_configure>

Construct the internal builder object safely. Returns exceptions or C<undef>.

  if( $test->configure ) { say "configure failed" }

=cut

sub safe_configure {
  my ($self) = @_;
  return exception { $self->configure };
}

sub _build_root {
  my ($self) = @_;
  return path( $self->builder->tempdir )->child('build');
}

sub _note_path_files {
  my ( $self, $root_path ) = @_;
  if ( not -e $root_path ) {
    $self->tb->diag("$root_path does not exist, not noting its contents");
  }
  my $i = path($root_path)->iterator( { recurse => 1 } );
  while ( my $path = $i->() ) {
    next if -d $path;
    $self->tb->note( "$path : " . $path->stat->size . q[ ] . $path->stat->mode );
  }
  return;
}

=method C<built_file>

Returns the named file if it exists in the build, C<undef> otherwise.

  my $file = $test->built_file('dist.ini');

=cut

sub built_file {
  my ( $self, $path ) = @_;
  my $root = $self->_build_root;
  return unless -e $root;
  return unless -d $root;
  my $file = $root->child( _file_list($path) );
  return unless -e $file;
  return if -d $file;
  return $file;
}

=method C<note_tempdir_files>

Recursively walk C<tempdir> and note its contents.

=cut

sub note_tempdir_files {
  my ($self) = @_;
  return $self->_note_path_files( $self->tempdir );
}

=method C<note_builddir_files>

Recursively walk C<builddir>(output) and note its contents.

=cut

sub note_builddir_files {
  my ($self) = @_;
  if ( -e $self->_build_root ) {
    return $self->_note_path_files( $self->_build_root );
  }
  $self->tb->note('No Build Root, probably due to no file gatherers');
  return;
}

sub _subtest_has_message {
  my ( $self, $regex, $reason ) = @_;
  my $log = $self->builder->log_messages;
  $self->tb->ok( scalar @{$log}, ' has messages' );
  return 1 if $self->_test_has_message( $log, $regex, $reason );
  $self->tb->diag( $self->tb->explain($log) );
  return;
}

=method C<has_message>

Assert there are messages, and this single message exists:

  $test->has_message( $regex, $description );

=cut

sub has_message {
  my ( $self, $regex, $reason ) = @_;
  $reason = ": $reason" if $reason;
  $reason = q[] unless $reason;
  return $self->tb->subtest(
    "log message check$reason" => sub {
      $self->tb->plan( tests => 2 );
      $self->_subtest_has_message( $regex, $reason );
    },
  );
}

=method C<run_command>

Execute a Dist::Zilla command in the constructed scratch directory.

  $test->run_command(['build','foo']);

The syntax is technically:

  $test->run_command( $argv, $arg );

But I'm yet to work out the meaning of the latter.

=cut

sub run_command {
  my ( $self, $argv, $arg ) = @_;
  return test_dzil( $self->tempdir, $argv, $arg );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

=begin Pod::Coverage

CAN_DPATH build CAN_EQORDIFF

=end Pod::Coverage

=head1 SYNOPSIS

  use Test::More;
  use Test::DZil qw( simple_ini );
  use Dist::Zilla::Util::Test::KENTNL qw( dztest );

  my $test = dztest;

  ## utility method.
  $test->add_file( 'dist.ini', simple_ini( .... ));

  ## build the dist
  # 1x subtest
  $test->build_ok;

  ## assert prereqs are identical to the hash
  ## extracting them from distmeta
  # 1x subtest
  $test->prereqs_deeply( { } );

  ## Test for specific log messages by regex
  # 1x subtest
  #  - tests there are messages
  #  - each regex must match a message
  my @list = (
    [ $regex, $indepdent_reason ],
    [ $regex ],
  );
  $test->has_messages( $reason, \@list );

  ## Test for any deep structure addressed
  ## By a Data::DPath expression
  # 1x subtest
  #   - asserts the expression returns a result
  #   - compares the structure against the expected one.
  $test->meta_path_deeply(
      '/author/*/[1]',
      [ 'E. Xavier Ample <example@example.org>' ],
      'The 1st author is the example author emitted by simple_ini'
  );

  ## Test for a file existing on the build side
  ## and return it if it exists.
  my $file = $test->test_has_built_file('dist.ini');

=cut
