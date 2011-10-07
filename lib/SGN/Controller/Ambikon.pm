package SGN::Controller::Ambikon;
use Moose;

BEGIN { extends 'Catalyst::Controller' }

use Ambikon::ServerHandle;

=head1 NAME

SGN::Controller::Ambikon - support for running the SGN app as an
Ambikon subsite.

=head1 PUBLIC ACTIONS

=head2 theme_template

Public path: /ambikon/theme_template

Serves a bare page with no content, suitable for use by Ambikon
theming postprocessors that consume the
L<Ambikon::IntegrationServer::Role::TemplateTheme> role.

=cut

sub theme_template : Path('/ambikon/theme_template') {
    my ( $self, $c ) = @_;
    $c->stash->{template} = '/ambikon/theme_template.mas';
}

=head1 PRIVATE ACTIONS

=head2 server

Returns the L<Ambikon::ServerHandle> for the current Ambikon Integration Server
(AIS) in use.  Also stashes it in C<< $c->stash->{ambikon_server} >>.
Returns nothing if not running under an AIS.

=cut

sub server : Private {
    my ( $self, $c, $server_url ) = @_;

    if( my $u = $c->req->header('X-Ambikon-Server-Url') ) {
        $server_url ||= $u;
    }

    return if not $server_url;

    return $c->stash->{ambikon_server} =
        Ambikon::ServerHandle->new( base_url => $server_url );
}

=head2 search_xrefs

Shortcut to call the search_xrefs method on the server handle returned
by server() above.

=cut

sub search_xrefs : Private {
    my ( $self, $c, @args ) = @_;
    my %args = $self->_xref_args( \@args );
    if( my $s = $self->server( $c ) ) {
        # if running under an ambikon server, query it for xrefs
        return $s->inflate( $s->search_xrefs( %args ) );
    } else {
        # if not running under an Ambikon server, call our own
        # xrefs-serving code and use those
        $c->stash->{xref_queries} = $args{queries};
        $c->stash->{xref_hints}   = $args{hints};
        $c->forward( '/ambikon/xrefs/search_xrefs' );
        my $xref_set = $c->stash->{xref_set};
        return {
            renderings => $c->stash->{xref_set}->renderings,
            'all_queries' => { SGN => { xref_set => $xref_set } },
        };
    }
}

sub _xref_args {
    my ( $self, $args ) = @_;
    return @$args == 1 ? ( queries => $args, hints => {} ) : @$args;
}

sub search_xrefs_html : Private {
    my ( $self, $c, @args ) = @_;
    my %args = $self->_xref_args( \@args );

    my $s = $self->server( $c )
        or return;

    return $s->search_xrefs_html( %args );
}

1;
