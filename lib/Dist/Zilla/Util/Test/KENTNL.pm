use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Util::Test::KENTNL;

our $VERSION = '1.000001';

#ABSTRACT: KENTNL's DZil plugin testing tool

# AUTHORITY

use Try::Tiny qw( try catch );
use Dist::Zilla::Tester qw( Builder );
use Sub::Exporter -setup => {
  exports => [ 'test_config', ],
  groups  => [ default => [qw( -all )] ],
};
use Test::DZil qw(simple_ini);

=method test_config

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
=cut

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

1;
