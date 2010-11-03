use strict;
use warnings;
package Dist::Zilla::Util::Test::KENTNL;
BEGIN {
  $Dist::Zilla::Util::Test::KENTNL::VERSION = '0.01000001';
}

#ABSTRACT: KENTNL's DZil plugin testing tool.

use Try::Tiny;
use Dist::Zilla::Tester qw( Builder );
use Params::Util qw(_HASH0);
use Moose::Autobox;

use Sub::Exporter -setup => {
  exports => [
    test_config =>
    simple_ini  => \'_simple_ini',
    dist_ini => '\_dist_ini',
  ],
  groups => [ default => [ qw( -all ) ] ]
};


sub test_config {
  my ( $conf ) = shift;
  my $args = [];
  if ( $conf->{dist_root} ) {
    $args->[0] = { dist_root => $conf->{dist_root} };
  }
  if ( $conf->{ini} ){
    $args->[1] ||= {};
    $args->[1]->{add_files} ||= {};
    $args->[1]->{add_files}->{'source/dist.ini'} = _simple_ini()->( $conf->{ini}->flatten );
  }
  my $build_error = undef;
  my $instance;
  try {
    $instance = Builder->from_config( $args->flatten );

    if ( $conf->{build} ){
      $instance->build();
    }
  } catch {
    $build_error = $_;
  };

  if ( $conf->{post_build_callback} ) {
    $conf->{post_build_callback}->({
      error => $build_error,
      instance => $instance,
    });
  }

  if ( $conf->{find_plugin} ){
    my $plugin = $instance->plugin_named( $conf->{find_plugin} );
    if ( $conf->{callback} ){
      my $error = undef;
      my $method = $conf->{callback}->{method};
      my $callargs   = $conf->{callback}->{args};
      my $call   = $conf->{callback}->{code};
      my $response;
      try {
        $response = $instance->$method( $callargs->flatten );
      } catch {
        $error = $_;
      };
      return $call->({
        error => $error,
        response => $response,
        instance => $instance,
      });
    } else {
      return $plugin;
    }
  }
}

sub _build_ini_builder {
  my ($starting_core) = @_;
  $starting_core ||= {};

  return sub {
    my (@arg) = @_;
    my $new_core = _HASH0($arg[0]) ? shift(@arg) : {};

    my $core_config = { $starting_core->flatten, $new_core->flatten };

    my $config = q{};

    for my $key ($core_config->keys) {
      my @values = ref $core_config->at( $key )
                 ? $core_config->at( $key )->flatten
                 : $core_config->at( $key );

      $config .= "$key = $_\n" for @values->grep(sub{ defined });
    }

    $config .= "\n" if length $config;

    for my $line (@arg) {
      my @plugin = ref $line ? $line->flatten : ($line, {});
      my $moniker = shift @plugin;
      my $name    = _HASH0($plugin[0]) ? undef : shift @plugin;
      my $payload = shift(@plugin) || {};
      if( @plugin ){
        require Carp;
        Carp::croak(q{TOO MANY ARGS TO PLUGIN GAHLGHALAGH});
      }

      $config .= '[' . $moniker;
      $config .= ' / ' . $name if defined $name;
      $config .= "]\n";

      for my $key ($payload->keys) {
        my @values = ref $payload->at( $key )
                   ?  $payload->at( $key )->flatten
                   : $payload->at( $key );

        $config .= "$key = $_\n" for @values;
      }

      $config .= "\n";
    }

    return $config;
  }
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _dist_ini {
  return _build_ini_builder;
}

sub _simple_ini {
  return _build_ini_builder({
    name     => 'DZT-Sample',
    abstract => 'Sample DZ Dist',
    version  => '0.001',
    author   => 'E. Xavier Ample <example@example.org>',
    license  => 'Perl_5',
    copyright_holder => 'E. Xavier Ample',
  });
}

1;

__END__
=pod

=head1 NAME

Dist::Zilla::Util::Test::KENTNL - KENTNL's DZil plugin testing tool.

=head1 VERSION

version 0.01000001

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

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2010 by Kent Fredric <kentnl@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

