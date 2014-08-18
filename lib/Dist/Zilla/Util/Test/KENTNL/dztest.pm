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
use Test::More qw( note explain pass fail diag subtest ok plan is is_deeply );
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
  return $self->builder;
}

sub safe_configure {
  my ($self) = @_;
  return exception {
    $self->configure;
  };
}

sub build {
  my ($self) = @_;
  return $self->builder->build;
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
  my ( undef, $root_path ) = @_;
  my $i = path($root_path)->iterator( { recurse => 1 } );
  while ( my $path = $i->() ) {
    next if -d $path;
    note "$path : " . $path->stat->size . q[ ] . $path->stat->mode;
  }
  return;
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
  return subtest 'Configure and build' => sub {
    plan tests => 2;
    for my $file ( values %{ $self->files } ) {
      next if -e $file and not -d $file;
      BAIL_OUT("expected file $file failed to add to tempdir");
    }
    $self->note_tempdir_files;

    is( $self->safe_configure, undef, "Can load config" );

    is( $self->safe_build, undef, "Can build" );

    $self->note_builddir_files;
    return;
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
    return;
  };
}

sub has_messages {
  my $nargs = ( my ( $self, $label, $map ) = @_ );

  if ( $nargs == 1 ) {
    croak "Invalid number of arguments ( < 2 )";
  }
  if ( $nargs == 2 ) {
    $map   = $label;
    $label = "log messages check";
  }
  if ( $nargs > 3 ) {
    croak "Invalid number of arguments ( > 3 )";
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
