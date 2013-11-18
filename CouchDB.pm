# simple json interface to couchdb
# found online

package CouchDB;

use strict;
use utf8;

use LWP::UserAgent;

sub new {
  my ($class, $host, $port, $options) = @_;

  my $ua = LWP::UserAgent->new;
  $ua->timeout(10);
  $ua->env_proxy;

  return bless {
                ua       => $ua,
                host     => $host,
                port     => $port,
                base_uri => "http://$host:$port/",
               }, $class;
}

sub ua { shift->{ua} }
sub base { shift->{base_uri} }

sub request {
  my ($self, $method, $uri, $content) = @_;

  my $full_uri = $self->base . $uri;
  my $req;

  if (defined $content) {
    #Content-Type: application/json

    $req = HTTP::Request->new( $method, $full_uri, undef, $content );
    $req->header('Content-Type' => 'application/json');
  } else {
    $req = HTTP::Request->new( $method, $full_uri );
  }

  my $response = $self->ua->request($req);

  if ($response->is_success) {
    if(defined wantarray) {
       return $response->content;
    }
  } else {
    die($response->status_line . ":" . $response->content);
  }
}

sub delete {
  my ($self, $url) = @_;

  $self->request(DELETE => $url);
}

sub get {
  my ($self, $url) = @_;

  $self->request(GET => $url);
}

sub put {
  my ($self, $url, $json) = @_;

  $self->request(PUT => $url, $json);
}

sub post {
  my ($self, $url, $json) = @_;

  $self->request(POST => $url, $json);
}

1;


