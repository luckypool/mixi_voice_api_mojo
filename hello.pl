#!/usr/bin/env perl
use Mojolicious::Lite;

# Documentation browser under "/perldoc"
plugin 'PODRenderer';

get '/' => sub {
    my $self = shift;
    unless (exists $self->session->{'access_token'}) {
        $self->render('index');
    }
    $self->render('logined');
};

get '/auth' => sub {
    my $self = shift;
    my $url = Mojo::URL->new('https://mixi.jp/connect_authorize.pl');
    $url->query([
            client_id => 'XXXXXXXXXX',
            response_type => 'code',
            scope => 'r_voice'
        ]);
    $self->redirect_to($url->to_abs);
};

get '/redirect' => sub{
    my $self = shift;
    my $url_for_get_token = Mojo::URL->new('https://secure.mixi-platform.com/2/token');
    $url_for_get_token->query([
            grant_type => 'authorization_code',
            client_id => 'XXXXXXXXXX',
            client_secret => 'XXXXXXXXXX',
            code => $self->param('code'),
            redirect_uri => 'http://localhost:3000/redirect'
        ]);
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $url_for_get_token => {
            'Content-Type' => 'application/x-www-form-urlencoded'
        }
    )->res->content->asset->slurp;
    my $token_json = Mojo::JSON->decode($res);
    $self->session(access_token => $token_json->{'access_token'});
    $self->session(refresh_token => $token_json->{'refresh_token'});
    $self->stash(url => '/');
    $self->render('redirect');
    $self->redirect_to('/');
};

app->start;

__DATA__
@@ redirect.html.ep
% layout 'default',  title => 'redirect';
redirect to <%= $url %>

