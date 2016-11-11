package MetaCPAN::Script::Tickets;

use strict;
use warnings;
use namespace::autoclean;

# Some issue with rt.cpan.org's cert
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;

use HTTP::Request::Common;
use IO::String;
use LWP::UserAgent;
use List::MoreUtils qw(uniq);
use List::Util qw(sum);
use Log::Contextual qw( :log :dlog );
use Moose;
use Parse::CSV;
use Pithub;
use URI::Escape qw(uri_escape);
use MetaCPAN::Types qw( HashRef );

with 'MetaCPAN::Role::Script', 'MooseX::Getopt';

has rt_summary_url => (
    is       => 'ro',
    required => 1,
    default  => 'https://rt.cpan.org/Public/bugs-per-dist.tsv',
);

has github_issues => (
    is       => 'ro',
    required => 1,
    default  => 'https://api.github.com/repos/%s/%s/issues?per_page=100',
);

has github_token => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_github_token',
);

has ua => (
    is      => 'ro',
    default => sub { LWP::UserAgent->new },
);

has pithub => (
    is      => 'ro',
    isa     => 'Pithub',
    lazy    => 1,
    builder => '_build_pithub',
);

has _bugs => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { +{} },
);

sub _build_github_token {
    my $self = shift;
    exists $self->config->{github_token}
        ? $self->config->{github_token}
        : undef;
}

sub _build_pithub {
    my $self = shift;
    return Pithub->new(
        per_page        => 100,
        auto_pagination => 1,
        ( $self->github_token ? ( token => $self->github_token ) : () )
    );
}

sub run {
    my $self = shift;
    $self->retrieve_rt_bugs();
    $self->retrieve_github_bugs();
    $self->index_bug_summary();
    return 1;
}

sub index_bug_summary {
    my $self = shift;
    $self->index->refresh;
    my $dists = $self->index->type('distribution');
    my $bulk = $self->index->bulk( size => 300 );
    for my $dist ( keys %{ $self->_bugs } ) {
        my $doc = $dists->get($dist);
        $doc ||= $dists->new_document( { name => $dist } );
        $doc->_set_bugs( $self->_bugs->{ $doc->name } );
        $bulk->put($doc);
    }
    $bulk->commit;
}

sub retrieve_github_bugs {
    my $self = shift;
    log_info {'Fetching GitHub issues'};

    my $scroll
        = $self->index->type('release')->find_github_based->scroll('5m');
    log_debug { sprintf( "Found %s repos", $scroll->total ) };
    my $summary = {};
    while ( my $release = $scroll->next ) {
        my $resources = $release->resources;
        my ( $user, $repo, $source )
            = $self->github_user_repo_from_resources($resources);
        next unless $user;
        log_debug {"Retrieving issues from $user/$repo"};
        my $open = $self->pithub->issues->list(
            user   => $user,
            repo   => $repo,
            params => { state => 'open' }
        );
        next unless ( $open->success );
        my $closed = $self->pithub->issues->list(
            user   => $user,
            repo   => $repo,
            params => { state => 'closed' }
        );
        next unless ( $closed->success );
        $summary->{ $release->{distribution} }
            = { open => 0, closed => 0, source => $source };
        $summary->{ $release->{distribution} }->{open}++
            while ( $open->next );
        $summary->{ $release->{distribution} }->{closed}++
            while ( $closed->next );
        $summary->{ $release->{distribution} }->{active}
            = $summary->{ $release->{distribution} }->{open};

    }

    $self->_bugs->{$_}{github} = $summary->{$_} for keys %{$summary};
}

# Try (recursively) to find a github url in the resources hash.
# FIXME: This should check bugtracker web exclusively, or at least first.
sub github_user_repo_from_resources {
    my ( $self, $resources ) = @_;
    my ( $user, $repo, $source );
    while ( my ( $k, $v ) = each %$resources ) {
        if ( !ref $v
            && $v
            =~ /^(https?|git):\/\/github\.com\/([^\/]+)\/([^\/]+?)(\.git)?\/?$/
            )
        {
            return ( $2, $3, $v );
        }
        ( $user, $repo, $source ) = $self->github_user_repo_from_resources($v)
            if ( ref $v eq 'HASH' );
        return ( $user, $repo, $source ) if ($user);
    }
    return ();
}

sub retrieve_rt_bugs {
    my $self = shift;
    log_info {'Fetching RT issues'};

    my $resp = $self->ua->request( GET $self->rt_summary_url );

    log_error { $resp->status_line } unless $resp->is_success;

    # NOTE: This is sending a byte string.
    my $rt = $self->parse_tsv( $resp->content );

    $self->_bugs->{$_}{rt} = $rt->{$_} for keys %{$rt};
}

sub parse_tsv {
    my ( $self, $tsv ) = @_;
    $tsv =~ s/^#\s*(dist\s.+)/$1/m;  # uncomment the field spec for Parse::CSV
    $tsv =~ s/^#.*\n//mg;

    # NOTE: This is byte-oriented.
    my $tsv_parser = Parse::CSV->new(
        handle   => IO::String->new($tsv),
        sep_char => "\t",
        names    => 1,
    );

    my %summary;
    while ( my $row = $tsv_parser->fetch ) {
        $summary{ $row->{dist} } = {
            source => $self->rt_dist_url( $row->{dist} ),
            active => $row->{active},
            closed => $row->{inactive},
            map { $_ => $row->{$_} + 0 }
                grep { not /^(dist|active|inactive)$/ }
                keys %$row,
        };
    }

    return \%summary;
}

sub rt_dist_url {
    my ( $self, $dist ) = @_;
    return 'https://rt.cpan.org/Public/Dist/Display.html?Name='
        . uri_escape($dist);
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 SYNOPSIS

 # bin/metacpan tickets

=head1 DESCRIPTION

Tracks the number of issues and the source, if the issue
tracker is RT or Github it fetches the info and updates
out ES information.

This can then be accessed here:

http://api.metacpan.org/distribution/Moose
http://api.metacpan.org/distribution/HTTP-BrowserDetect

=cut

