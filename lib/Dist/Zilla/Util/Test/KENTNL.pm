use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Util::Test::KENTNL;

our $VERSION = '1.000004';

#ABSTRACT: KENTNL's DZil plugin testing tool

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Try::Tiny qw( try catch );
use Dist::Zilla::Tester qw( Builder );
use Sub::Exporter -setup => {
  exports => [ 'test_config', 'dztest' ],
  groups => [ default => [qw( -all )] ],
};
use Test::DZil qw(simple_ini);




























































































sub test_config {
  my ($conf) = shift;
  my $args = [];
  if ( $conf->{dist_root} ) {
    $args->[0] = { dist_root => $conf->{dist_root} };
  }
  if ( $conf->{ini} ) {
    $args->[1] ||= {};
    $args->[1]->{add_files} ||= {};
    $args->[1]->{add_files}->{'source/dist.ini'} = simple_ini( @{ $conf->{ini} } );
  }
  my $build_error = undef;
  my $instance;
  try {
    $instance = Builder()->from_config( @{$args} );

    if ( $conf->{build} ) {
      $instance->build();
    }
  }
  catch {
    $build_error = $_;
  };

  # post_build_callback can be used like an error handler of sorts.
  # ( Sort of a deferred but pre-defined catch clause )
  # if its defined its called, and no native build errors should occur

  # without this defined, if an error occurs, we rethrow it with die

  if ( $conf->{post_build_callback} ) {
    $conf->{post_build_callback}->(
      {
        error    => $build_error,
        instance => $instance,
      }
    );
  }
  elsif ( defined $build_error ) {
    require Carp;
    Carp::croak $build_error;
  }

  if ( $conf->{find_plugin} ) {
    my $plugin = $instance->plugin_named( $conf->{find_plugin} );
    if ( $conf->{callback} ) {
      my $error    = undef;
      my $method   = $conf->{callback}->{method};
      my $callargs = $conf->{callback}->{args};
      my $call     = $conf->{callback}->{code};
      my $response;
      try {
        $response = $instance->$method( $callargs->flatten );
      }
      catch {
        $error = $_;
      };
      return $call->(
        {
          plugin   => $plugin,
          error    => $error,
          response => $response,
          instance => $instance,
        }
      );
    }
    return $plugin;
  }

  return $instance;
}

sub dztest {
  my (@args) = @_;
  return Dist::Zilla::Util::Test::KENTNL::_dztest->new(@args);
}

{

  package Dist::Zilla::Util::Test::KENTNL::_dztest;
  use Moose;
  use Test::DZil;
  use Test::Fatal;
  use Test::More qw( note explain pass fail diag subtest ok );
  use Path::Tiny qw(path);

  has files => (
    is   => ro =>,
    lazy => 1,
    default => sub { return {}; },
  );

  has tempdir => (
    is      => ro =>,
    lazy    => 1,
    default => sub {
      my $tempdir = Path::Tiny->tempdir;
      note "Creating fake dist in $tempdir";
      return $tempdir;
    },
  );

  has builder => (
    is         => ro =>,
    lazy_build => 1,
  );

  sub add_file {
    my ( $self, $path, $content ) = @_;
    my $target = $self->tempdir->child($path);
    $target->parent->mkpath;
    $target->spew($content);
    $self->files->{ $target->relative( $self->tempdir ) } = $target;
    return;
  }

  sub has_source_file {
    my ( $self, $path ) = @_;
    return unless -e $self->tempdir->child($path);
    return -f $self->tempdir->child($path);
  }

  sub _build_builder {
    my ($self) = @_;
    return Builder->from_config( { dist_root => q[] . $self->tempdir } );
  }

  sub configure {
    my ($self) = @_;
    $self->builder;
  }

  sub safe_configure {
    my ($self) = @_;
    return exception {
      $self->configure;
    };
  }

  sub build {
    my ($self) = @_;
    $self->builder->build;
  }

  sub safe_build {
    my ($self) = @_;
    return exception {
      $self->build;
    };
  }

  sub _build_root {
    my ($self) = @_;
    return path( $self->builder->tempdir )->child('build');
  }

  sub _note_path_files {
    my ( $self, $path ) = @_;
    my $i = path($path)->iterator( { recurse => 1 } );
    while ( my $path = $i->() ) {
      next if -d $path;
      note "$path : " . $path->stat->size . " " . $path->stat->mode;
    }
  }

  sub note_tempdir_files {
    my ($self) = @_;
    $self->_note_path_files( $self->tempdir );
  }

  sub note_builddir_files {
    my ($self) = @_;
    $self->_note_path_files( $self->_build_root );
  }

  sub built_json {
    my ($self) = @_;
    return $self->builder->distmeta;
  }

  sub build_ok {
    my ($self) = @_;
    return subtest 'Configure and build' => sub {
      plan tests => 2;
      for my $file ( values %{ $self->files } ) {
        next if -e $file and -f $file;
        BAIL_OUT("expected file $file failed to add to tempdir");
      }
      $self->note_tempdir_files;

      is( $self->safe_configure, undef, "Can load config" );

      is( $self->safe_build, undef, "Can build" );

      $self->note_builddir_files;
    };
  }

  sub prereqs_deeply {
    my ( $self, $prereqs ) = @_;
    return subtest "distmeta prereqs comparison" => sub {
      plan tests => 2;
      ok( defined $self->built_json, 'distmeta defined' );
      my $meta = $self->built_json;
      note explain $meta->{prereqs};
      is_deeply( $meta->{prereqs}, $prereqs, "Prereqs match expected set" );
    };
  }

  sub has_messages {
    my $nargs = ( my ( $self, $label, $map ) = @_ );

    if ( $nargs == 1 ) {
      die "Invalid number of arguments ( < 2 )";
    }
    if ( $nargs == 2 ) {
      $map   = $label;
      $label = "log messages check";
    }
    if ( $nargs > 3 ) {
      die "Invalid number of arguments ( > 3 )";
    }
    return subtest $label => sub {
      plan tests => 1 + scalar @{$map};
      my $log = $self->builder->log_messages;
      ok( scalar @{$log}, ' has messages' );
      my $need_diag;
    test: for my $entry ( @{$map} ) {
        my ( $regex, $reason ) = @{$entry};
        $reason = ": $reason" if $reason;
        $reason = "" unless $reason;
        my $i = 0;
        for my $item ( @{$log} ) {
          if ( $item =~ $regex ) {
            note qq[item $i: ], explain $item;
            pass("log message $i matched $regex$reason");
            next test;
          }
          $i++;
        }
        $need_diag = 1;
        fail("No log messages matched $regex$reason");
      }
      if ($need_diag) {
        diag explain $log;
      }
    };

  }

  sub had_message {
    my ( $self, $regex, $reason ) = @_;
    return subtest "log message check: $reason" => sub {
      plan tests => 2;
      my $log = $self->builder->log_messages;
      ok( scalar @{$log}, ' has messages' );
      my $i = 0;
      for my $item ( @{$log} ) {
        if ( $item =~ $regex ) {
          note qq[item $i: ], explain $item;
          pass("log message $i matched $regex");
          return;
        }
        $i++;
      }
      diag explain $log;
      fail("No log messages matched $regex");
    };
  }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Util::Test::KENTNL - KENTNL's DZil plugin testing tool

=head1 VERSION

version 1.000004

=head1 METHODS

=head2 test_config

This is pretty much why this module exists. Its a little perverse, but makes testing WAY easier.

  my $plugin = test_config({
    dist_root => 'corpus/dist/DZT',
    ini       => [
      'GatherDir',
      [ 'Prereqs' => { 'Test::Simple' => '0.88' } ],
    ],
    post_build_callback => sub {
        my $config = shift;
        # Handy place to put post-construction test code.
        die $config->{error} if $config->{error};
    },
    find_plugin => 'SomePluginName'
  });

Additionally, you can add this section

  callback => {
    method => 'metadata',
    args   => [],
    code   => sub {
      my $data = shift;
      print "Errors ( if any ) $data->{error} ";
      dump  $data->{response}; # response from ->metadata
      $data->{instance}->doMorestuffbyhand();
      # ok( .... 'good place for a test!' )
    },
  }

Generally, I find it easier to do 1-off function wrappers, i.e.:

  sub make_plugin {
    my @args = @_;
    return test_config({
        dist_root => 'corpus/dist/DZT',
        ini => [
          'GatherDir',
          [ 'Prereqs' => {'Test::Simple' => '0.88' } ],
          [ 'FakePlugin' => {@args } ],
        ],
        post_build_callback => sub {
          my $config = shift;
          die $config->{error} if $config->{error};
        },
        find_plugin => 'FakePlugin',
    });
  }

Which lets us do

  ok( make_plugin( inherit_version => 1 )->inherit_version , 'inherit_verion = 1 propagates' );

=head4 parameters

  my $foo = test_config({
      dist_root => 'Some/path'    # optional, strongly recommended.
      ini       => [              # optional, strongly recommended.
          'BasicPlugin',
          [ 'AdvancedPlugin' => { %pluginargs }],
      ],
      build    => 0/1              # works fine as 0, 1 tells it to call the ->build() method.
      post_build_callback => sub {
        my ( $conf )  = shift;
        $conf->{error}    # any errors that occured during construction/build
        $conf->{instance} # the constructed instance
        # this is called immediately after construction, do what you will with this.
        # mostly for convenience
      },
      find_plugin => 'Some::Plugin::Name', # makes test_config find and return the plugin that matched that name instead of
                                           # the config instance

      callback => {                        # overrides the return value of find_plugin if it is called
        method => 'method_to_call',
        args   => [qw( hello world )],
        code   => sub {
          my ($conf) = shift;
          $conf->{plugin}   # the constructed plugin instance
          $conf->{error}    # any errors discovered when calling ->method( args )
          $conf->{instance} # the zilla instance
          $conf->{response} # the return value of ->method( args )
          # mostly just another convenience of declarative nature.
          return someValueHere # this value will be returned by test_config
        }
      },
  });

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Kent Fredric <kentnl@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
