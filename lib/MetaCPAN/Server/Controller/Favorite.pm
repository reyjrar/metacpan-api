package MetaCPAN::Server::Controller::Favorite;

use strict;
use warnings;

use Moose;

BEGIN { extends 'MetaCPAN::Server::Controller' }

with 'MetaCPAN::Server::Role::JSONP';
with 'MetaCPAN::Server::Role::ES::Query';

sub find : Path('') : Args(2) {
    my ( $self, $c, $user, $distribution ) = @_;
    eval {
        my $favorite = $self->model($c)->raw->get(
            {
                user         => $user,
                distribution => $distribution
            }
        );
        $c->stash( $favorite->{_source} || $favorite->{fields} );
    } or $c->detach( '/not_found', [$@] );
}

sub by_user : Path('by_user') : Args(0) {
    my ( $self, $c ) = @_;
    my @users = split /,/ => $c->req->parameters->{users};
    $self->es_query_by_key( $c, 'user', \@users );
}

__PACKAGE__->meta->make_immutable;
1;
