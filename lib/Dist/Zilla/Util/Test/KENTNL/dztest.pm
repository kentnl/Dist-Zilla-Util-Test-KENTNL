use 5.008;    # utf8
use strict;
use warnings;
use utf8;

package Dist::Zilla::Util::Test::KENTNL::dztest;

our $VERSION = '1.000004';

# ABSTRACT: Shared dist testing logic for easy dzil things

our $AUTHORITY = 'cpan:KENTNL'; # AUTHORITY

use Carp qw( croak );
use Moose qw( has );
use Test::DZil qw( Builder );
use Test::Fatal qw( exception );
use Test::More qw( );
use Path::Tiny qw(path);
use Data::DPath qw( dpath );

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

sub source_file {
  my ( $self, $path ) = @_;
  my $file = $self->tempdir->child($path);
  return unless -e $file;
  return if -d $file;
  return $file;
}

sub _build_builder {
  my ($self) = @_;
  return Builder->from_config( { dist_root => q[] . $self->tempdir } );
}

sub configure {
  my ($self) = @_;
  return $self->builder;
}

sub safe_configure {
  my ($self) = @_;
  return exception { $self->configure };
}

sub build {
  my ($self) = @_;
  return $self->builder->build;
}

sub safe_build {
  my ($self) = @_;
  return exception { $self->build };
}

sub _build_root {
  my ($self) = @_;
  return path( $self->builder->tempdir )->child('build');
}

sub _note_path_files {
  my ( $self, $root_path ) = @_;
  my $i = path($root_path)->iterator( { recurse => 1 } );
  while ( my $path = $i->() ) {
    next if -d $path;
    $self->tb->note( "$path : " . $path->stat->size . q[ ] . $path->stat->mode );
  }
  return;
}

sub test_has_built_file {
  my ( $self, @path ) = @_;
  my $file = $self->_build_root->child(@path);
  if ( defined $file and -e $file and not -d $file ) {
    $self->tb->ok( 1, "$file exists" );
    return $file;
  }
  $self->tb->ok( undef, "$file exists" );
  return;
}

sub built_file {
  my ( $self, @path ) = @_;
  my $file = $self->_build_root->child(@path);
  return unless -e $file;
  return if -d $file;
  return $file;
}

sub note_tempdir_files {
  my ($self) = @_;
  return $self->_note_path_files( $self->tempdir );
}

sub note_builddir_files {
  my ($self) = @_;
  return $self->_note_path_files( $self->_build_root );
}

sub built_json {
  my ($self) = @_;
  return $self->builder->distmeta;
}

sub build_ok {
  my ($self) = @_;
  return $self->tb->subtest(
    'Configure and build' => sub {
      $self->tb->plan( tests => 2 );
      for my $file ( values %{ $self->files } ) {
        next if -e $file and not -d $file;
        $self->tb->BAIL_OUT("expected file $file failed to add to tempdir");
      }
      $self->note_tempdir_files;

      $self->tb->is_eq( $self->safe_configure, undef, 'Can load config' );

      $self->tb->is_eq( $self->safe_build, undef, 'Can build' );

      $self->note_builddir_files;
      return;
    },
  );
}

sub prereqs_deeply {
  my ( $self, $prereqs ) = @_;
  return $self->tb->subtest(
    'distmeta prereqs comparison' => sub {
      $self->tb->plan( tests => 2 );
      $self->tb->ok( defined $self->built_json, 'distmeta defined' );
      my $meta = $self->built_json;
      $self->tb->note( $self->tb->explain( $meta->{prereqs} ) );
      Test::More::is_deeply( $meta->{prereqs}, $prereqs, 'Prereqs match expected set' );
      return;
    },
  );
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
      my $log = $self->builder->log_messages;
      $self->tb->ok( scalar @{$log}, ' has messages' );
      my $need_diag;
    MESSAGETEST: for my $entry ( @{$map} ) {
        my ( $regex, $reason ) = @{$entry};
        $reason = ": $reason" if $reason;
        $reason = q[] unless $reason;
        my $i = 0;
        for my $item ( @{$log} ) {
          if ( $item =~ $regex ) {
            $self->tb->note( qq[item $i: ], $self->tb->explain($item) );
            $self->tb->ok( 1, "log message $i matched $regex$reason" );
            next MESSAGETEST;
          }
          $i++;
        }
        $need_diag = 1;
        $self->tb->ok( undef, "No log messages matched $regex$reason" );
      }
      if ($need_diag) {
        $self->tb->diag( $self->tb->explain($log) );
      }
    },
  );

}

sub has_message {
  my ( $self, $regex, $reason ) = @_;
  $reason = ": $reason" if $reason;
  $reason = q[] unless $reason;
  return $self->tb->subtest(
    "log message check$reason" => sub {
      $self->tb->plan( tests => 2 );
      my $log = $self->builder->log_messages;
      $self->tb->ok( scalar @{$log}, ' has messages' );
      my $i = 0;
      for my $item ( @{$log} ) {
        if ( $item =~ $regex ) {
          $self->tb->note( qq[item $i: ], $self->tb->explain($item) );
          $self->tb->ok( 1, "log message $i matched $regex" );
          return;
        }
        $i++;
      }
      $self->tb->diag( $self->tb->explain($log) );
      $self->tb->ok( undef, "No log messages matched $regex" );
    },
  );
}

sub meta_path_deeply {
  my ( $self, $expression, $expected, $reason ) = @_;
  if ( not $reason ) {
    $reason = "distmeta at $expression matches expected";
  }
  return $self->tb->subtest(
    $reason => sub {
      $self->tb->plan( tests => 2 );
      my (@results) = dpath($expression)->match( $self->builder->distmeta );
      $self->tb->ok( @results > 0, "distmeta matched expression $expression" );
      $self->tb->note( $self->tb->explain( \@results ) );
      Test::More::is_deeply( \@results, $expected, 'distmeta matched expectations' );
      return;
    },
  );
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Util::Test::KENTNL::dztest - Shared dist testing logic for easy dzil things

=head1 VERSION

version 1.000004

=head1 AUTHOR

Kent Fredric <kentnl@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Kent Fredric <kentnl@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
