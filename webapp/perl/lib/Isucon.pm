package Isucon;

use strict;
use warnings;
use utf8;
use Kossy;
use DBI;
use JSON;
use Cache::Memcached::Fast;
use LWP::UserAgent;
our $VERSION = 0.01;

sub load_config {
    my $self = shift;
    return $self->{_config} if $self->{_config};
    open( my $fh, '<', $self->root_dir . '/../config/hosts.json') or die $!;
    local $/;
    my $json = <$fh>;
    $self->{_config} = decode_json($json);
}

sub dbh {
    my $self = shift;
    my $config = $self->load_config;
    my $host = $config->{servers}->{database}->[0] || '127.0.0.1';
    DBI->connect_cached('dbi:mysql:isucon;host='.$host,'isuconapp','isunageruna',{
        RaiseError => 1,
        PrintError => 0,
        ShowErrorStatement => 1,
        AutoInactiveDestroy => 1,
        mysql_enable_utf8 => 1
    });
}

my $memd;
sub cache {
    my $self = shift;
    return $memd if $memd;
    my $config = $self->load_config;
    $memd = Cache::Memcached::Fast->new({
        servers => $config->{servers}{memcached},
    });
}

filter 'recent_commented_articles' => sub {
    my $app = shift;
    sub {
        my ( $self, $c )  = @_;
        $c->stash->{recent_commented_articles} = $self->dbh->selectall_arrayref(
            'SELECT id, title FROM article ORDER BY comment_created_at DESC LIMIT 10',
            { Slice => {} });
        $app->($self,$c);
    }
};

get '/' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    my $rows = $self->dbh->selectall_arrayref(
        'SELECT id,title,body,created_at FROM article ORDER BY id DESC LIMIT 10',
        { Slice => {} });
    $c->render('index.tx', { articles => $rows });
};

get '/article/:articleid' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    my $article = $self->dbh->selectrow_hashref(
        'SELECT id,title,body,created_at FROM article WHERE id=?',
        {}, $c->args->{articleid});
    my $comments = $self->dbh->selectall_arrayref(
        'SELECT name,body,created_at FROM comment WHERE article=? ORDER BY id',
        { Slice => {} }, $c->args->{articleid});

    my $res = $c->render('article.tx', { article => $article, comments => $comments });

    $self->cache->set('/article/'.$c->args->{articleid} => $res->body, 5);
    $res;
};

get '/post' => [qw/recent_commented_articles/] => sub {
    my ( $self, $c )  = @_;
    $c->render('post.tx');
};

post '/post' => sub {
    my ( $self, $c )  = @_;
    my $sth = $self->dbh->prepare('INSERT INTO article SET title = ?, body = ?');
    $sth->execute($c->req->param('title'), $c->req->param('body'));
    $c->redirect($c->req->uri_for('/'));
};

post '/comment/:articleid' => sub {
    my ( $self, $c )  = @_;

    my $sth = $self->dbh->prepare('INSERT INTO comment SET article = ?, name =?, body = ?');
    $sth->execute(
        $c->args->{articleid},
        $c->req->param('name'),
        $c->req->param('body')
    );

    $sth = $self->dbh->prepare('UPDATE article SET comment_created_at = NOW() WHERE id = ?');
    $sth->execute(
        $c->args->{articleid},
    );

    my $ua = LWP::UserAgent->new;

    my $header = HTTP::Headers->new;
    $header->header('Host' => '125.6.147.165');
    my $req = HTTP::Request->new(
        'GET' => 'http://localhost:5000/article/'.$c->args->{articleid},
        $header,
    );
    my $res = $ua->request($req);

    $c->redirect($c->req->uri_for('/article/'.$c->args->{articleid}));
};

1;

