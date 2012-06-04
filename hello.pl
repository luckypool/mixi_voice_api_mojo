#!/usr/bin/env perl
use Mojolicious::Lite;
use Data::Dumper;

my $CREDENTIAL_INFO = {
    CONSUMER_KEY => 'XXXX',
    CONSUMER_SECRET => 'XXXX',
    REDIRECT_URI => 'http://localhost:3000/redirect'
};

my $SCOPE_INFO = 'r_voice w_voice';

sub __get_access_token {
    my ($code) = @_;
    # Mojo::URLでURLをつくる
    my $url_for_get_token = Mojo::URL->new('https://secure.mixi-platform.com/2/token');
    $url_for_get_token->query([
            grant_type => 'authorization_code',
            client_id => $CREDENTIAL_INFO->{CONSUMER_KEY},,
            client_secret => $CREDENTIAL_INFO->{CONSUMER_SECRET},
            code => $code,
            redirect_uri => $CREDENTIAL_INFO->{REDIRECT_URI}
        ]);
    # Mojo::UserAgentを使ってPOSTリクエスト
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $url_for_get_token => {
            'Content-Type' => 'application/x-www-form-urlencoded'
        }
    )->res->content->asset->slurp;
    return $res;
}

sub __refresh_access_token {
    my ($refresh_token) = @_;
    # Mojo::URLでURLをつくる
    my $url_for_get_token = Mojo::URL->new('https://secure.mixi-platform.com/2/token');
    $url_for_get_token->query([
            grant_type => 'refresh_token',
            client_id => $CREDENTIAL_INFO->{CONSUMER_KEY},,
            client_secret => $CREDENTIAL_INFO->{CONSUMER_SECRET},
            refresh_token => $refresh_token
        ]);
    # Mojo::UserAgentを使ってPOSTリクエスト
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $url_for_get_token => {
            'Content-Type' => 'application/x-www-form-urlencoded'
        }
    )->res->content->asset->slurp;

    my $token_json = Mojo::JSON->decode($res);

    return exists $token_json->{error} ? { error_info => $token_json->{error} }
    : {
        access_token => $token_json->{access_token},
        refresh_token => $token_json->{refresh_token},
        expires_in => $token_json->{expires_in}
    };
}

sub __get_friends_timeline {
    my ($access_token) = @_;
    my $url_for_get_timeline = Mojo::URL->new("https://api.mixi-platform.com/2/voice/statuses/friends_timeline");
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get(
        $url_for_get_timeline => {
            'Authorization' => "OAuth $access_token"
        }
    )->res->content->asset->slurp;
    return Mojo::JSON->decode($res);
}

sub __get_user_timeline {
    my ($access_token, $user_id) = @_;
    my $url_for_get_timeline = Mojo::URL->new("https://api.mixi-platform.com/2/voice/statuses/$user_id/user_timeline");
    # Mojo::UserAgentを使ってGETリクエスト
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->get(
        $url_for_get_timeline => {
            'Authorization' => "OAuth $access_token"
        }
    )->res->content->asset->slurp;
    return Mojo::JSON->decode($res);
}

sub __post_voice {
    my ($access_token,  $status) = @_;
    my$url_for_post_voice = Mojo::URL->new("https://api.mixi-platform.com/2/voice/statuses");
    $url_for_post_voice->query([
            status => $status
        ]);
    my $ua = Mojo::UserAgent->new;
    my $res = $ua->post(
        $url_for_post_voice => {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'Authorization' => "OAuth $access_token"
        }
    )->res->content->asset->slurp;
    print Dumper($res);
    return Mojo::JSON->decode($res);
}

get '/' => sub {
    my $self = shift;
    unless (exists $self->session->{access_token}) {
        return $self->render('index');
    }

    my $refreshed_token = __refresh_access_token($self->session->{refresh_token});
    if (exists $refreshed_token->{error_info}){
        $self->session(expires => 1);
        $self->flash(error_info => $refreshed_token->{error_info}+' (Maybe, session-timeout)');
        return $self->redirect_to('/error');
    }
    $self->session(access_token => $refreshed_token->{access_token});
    $self->session(refresh_token => $refreshed_token->{refresh_token});
    $self->session(expires => time + $refreshed_token->{expires_in});

    $self->render('logined');
};

get '/auth' => sub {
    my $self = shift;
    my $url = Mojo::URL->new('https://mixi.jp/connect_authorize.pl');
    $url->query([
            client_id => $CREDENTIAL_INFO->{CONSUMER_KEY},
            response_type => 'code',
            scope => $SCOPE_INFO
        ]);
    $self->redirect_to($url->to_abs);
};

get '/logout' => sub {
    my $self = shift;
    # セッションを破棄
    $self->session(expires => 1);
    $self->redirect_to('/');
};

get '/error' => sub {
    my $self = shift;
    $self->stash(
        error_info =>
        exists $self->session->{flash} ?
        $self->session->{flash}->{error_info} :
        'error!!'
    );
    $self->render('error');
};

get '/redirect' => sub{
    my $self = shift;
    unless (defined $self->param('code')){
        return $self->redirect_to('/');
    }

    my $token_json = Mojo::JSON->decode(__get_access_token($self->param('code')));

    if (exists $token_json->{error}){
        $self->flash(error_info => $token_json->{error});
        return $self->redirect_to('/error');
    }

    # access_tokenなどをセッションに保存
    $self->session(access_token => $token_json->{access_token});
    $self->session(refresh_token => $token_json->{refresh_token});
    $self->session(expires => time + $token_json->{expires_in});
    $self->stash(url => '/');
    $self->render('redirect');

    # ルートページにリダイレクト
    $self->redirect_to('/');

};

post '/voice' => sub {
    my $self = shift;
    my $status = $self->param('status');
    __post_voice($self->session->{access_token}, $status);
    $self->redirect_to('/voice');
};

get '/voice' => sub {
    my $self = shift;
    my $user_timeline_json = __get_user_timeline($self->session->{access_token}, '@me');
    my $friends_timeline_json = __get_friends_timeline($self->session->{access_token});
    $self->stash(
        user_timeline => $user_timeline_json,
        friends_timeline => $friends_timeline_json
    );
    $self->render('voice');
};

app->start;

