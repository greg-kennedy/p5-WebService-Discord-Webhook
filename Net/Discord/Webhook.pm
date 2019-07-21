#!/usr/bin/env perl
package Net::Discord::Webhook;

use strict;
use warnings;

# Module for interacting with the REST service
use LWP::UserAgent;
# JSON decode
use JSON::PP qw(encode_json decode_json);
# Base64 encode for avatar images
use MIME::Base64 qw(encode_base64);
# better error messages
use Carp qw(croak carp);

# PACKAGE VARS
our $VERSION = '1.00';

# Base URL for all API requests
our $BASE_URL = 'https://discordapp.com/api';

#use Data::Dumper;

##################################################

# Create a new Webhook object.
#  Pass either a bare hash or hash reference
#  Requires:
#   url, or
#   token and id
#  Optional:
#   timeout
sub new
{
  my $class = shift;

  my %params;
  if (ref($_[0]) eq 'HASH') {
    %params = %{+shift};
  }
  elsif (ref($_[0]) eq 'ARRAY') {
    (%params) = @{+shift};
  }
  elsif (ref($_[0]) eq 'SCALAR') {
    $params{url} = ${+shift};
  }
  elsif (scalar @_ > 1) {
    (%params) = @_;
  }
  else {
    $params{url} = shift;
  }

  # check parameters
  my ($id, $token);
  if (defined $params{url}) {
    if ($params{url} =~ m/^\Q$BASE_URL\E\/webhooks\/(\d+)\/([^\/?]+)/) {
      $id = $1;
      $token = $2;
    }
    else { croak "Failed to parse ID and Token from URL" }
  }
  elsif (defined $params{id} && defined $params{token}) {
    if ($params{id} =~ m/^\d+$/ && $params{token} =~ m/^[^\/?]+$/) {
      $id = $params{id};
      $token = $params{token};
    }
    else { croak "Failed to validate ID and Token" }
  }
  else { croak "Must provide either URL, or ID and Token" }

  # Create an LWP UserAgent for REST requests
  my $ua = LWP::UserAgent->new;
  $ua->agent('p5-Net-Discord-Webhook (https://github.com/greg-kennedy/p5-Net-Discord-Webhook, ' . $VERSION . ')');
  $ua->env_proxy;
  $ua->cookie_jar( {} );

  if ($params{timeout}) { $ua->timeout( $params{timeout} ) }

  # create class with some params
  my $self = bless { id => $id, token => $token, ua => $ua }, $class;

  # call get to populate additional details
  #$self->get();

  return $self;
}

# updates internal structures after a webhook request
sub _parse_response {
  my $self = shift;
  my $response = shift;

  # sanity
  if ($self->{id} ne $response->{id}) {
    carp "Warning: get() returned ID='" . $response->{id} . "', expected ID='" . $self->{id} . "'"
  }
  if ($self->{token} ne $response->{token}) {
    carp "Warning: get() returned Token='" . $response->{token} . "', expected Token='" . $self->{token} . "'"
  }

  # store / update details
  if (exists $response->{guild_id}) { $self->{guild_id} = $response->{guild_id} }
  $self->{channel_id} = $response->{channel_id};
  $self->{name} = $response->{name};
  $self->{avatar} = $response->{avatar};

  return $response;
}

# GET request
#  Retrieves some info about the webhook setup
sub get {
  my $self = shift;

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};
  my $response = $self->{ua}->get($url);
  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->get($url) returned: " . $response->status_line . " '" . $response->decoded_content . "'";
    return undef;
  }

  # empty result
  if (! $response->decoded_content) { return {} }

  # update internal structs and return
  return $self->_parse_response(decode_json($response->decoded_content));
}

# PATCH request
#  Allows webhook to alter its Name or Avatar
sub modify {
  my $self = shift;

  my %params;
  my $json;
  if (ref($_[0]) eq 'HASH') {
    %params = %{+shift};
  } elsif (ref($_[0]) eq 'ARRAY') {
    (%params) = @{+shift};
  } elsif (ref($_[0]) eq 'SCALAR') {
    $json = ${+shift};
  }
  elsif (scalar @_ > 1) {
    (%params) = @_;
  }
  else {
    $json = shift;
  }

  my %request;

  # retrieve the two allowed params and place in request if needed
  if (defined $params{name}) { $request{name} = $params{name} }

  if (exists $params{avatar}) {
    if (defined $params{avatar}{data}) {
      my $type;
      if (defined $params{avatar}{type}) {
        my $desired_type = lc($params{avatar}{type});

        if ($desired_type eq 'jpg' || $desired_type eq 'jpeg' || $desired_type eq 'image/jpg' || $desired_type eq 'image/jpeg') {
          $type = 'image/jpeg';
        } elsif ($desired_type eq 'png' || $desired_type eq 'image/png') {
          $type = 'image/png';
        } elsif ($desired_type eq 'gif' || $desired_type eq 'image/gif') {
          $type = 'image/gif';
        } else {
          $type = $desired_type;
        }
      } else {
        # try to infer type from data string
        if (substr($params{avatar}{data}, 0, 8) eq "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a") {
          $type = 'image/png';
        } elsif (substr($params{avatar}{data}, 0, 2) eq "\xff\xd8" && substr($params{avatar}{data}, -2) eq "\xff\xd9") {
          $type = 'image/jpeg';
        } elsif (substr($params{avatar}{data}, 0, 4) eq 'GIF8') {
          $type = 'image/gif';
        } else {
          croak "Could not determine image type from data";
        }
      }

      $request{avatar} = 'data:' . $type . ';base64,' . encode_base64($params{avatar}{data});

    } else {
      $request{avatar} = undef;
    }
  }

  if (! %request) {
    carp "Modify request with no valid parameters";
    return undef;
  }

  #my $response = $self->_req('/webhooks/' . $self->{id} . '/' . $self->{token}, 'PATCH', \%request);

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};
  my $response = $self->{ua}->patch($url, \%request);
  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->patch($url) returned: " . $response->status_line . " (" . $response->decoded_content . ")";
    return undef;
  }

  # empty result
  if (! $response->decoded_content) { return {} }

  # update internal structs and return
  return $self->_parse_response(decode_json($response->decoded_content));
}

sub delete {
  my $self = shift;

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};
  my $response = $self->{ua}->delete($url);
  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->delete($url) returned: " . $response->status_line . " (" . $response->decoded_content . ")";
    return undef;
  }

  # return details
  return $response;
}

sub execute {
  my $self = shift;

  # extract params
  my %params;
  my $wait;
  if (ref($_[0]) eq 'HASH') {
    %params = %{+shift};
    $wait = shift;
  } elsif (ref($_[0]) eq 'ARRAY') {
    (%params) = @{+shift};
    $wait = shift;
  }
  elsif (ref($_[0]) eq 'SCALAR') {
    $params{content} = ${+shift};
  }
  elsif (scalar @_ > 1) {
    (%params) = @_;
  }
  else {
    $params{content} = shift;
  }

  if (!defined $wait) { $wait = delete $params{wait} }

  # compose URL
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};
  if ($wait) { $url .= '?wait=true' }

  # test required fields
  if (!defined $params{content} && !defined $params{embed} && !defined $params{embeds} && !defined $params{file})
  {
    croak "Execute request missing required parameters (must have at least content, embeds or file)";
  }

  # construct JSON request
  my %request;
  if ($params{content}) { $request{content} = $params{content} }

  if ($params{embeds}) { $request{embeds} = $params{embeds} }
  elsif ($params{embed}) { $request{embeds} = [ $params{embed} ] }

  if (defined $params{username}) { $request{username} = $params{username} }
  if (defined $params{avatar_url}) { $request{avatar_url} = $params{avatar_url} }
  if ($params{tts}) { $request{tts} = JSON::PP::true }

  # switch mode for request based on file upload or no
  my $response;
  if (!defined $params{file}) {
    $response = $self->{ua}->post($url, Content => encode_json(\%request), 'Content-Type' => 'application/json');
  } else {
    croak "File uploads are not supported at this time";
  }

  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->post($url) returned: " . $response->status_line . " (" . $response->decoded_content . ")";
    return undef;
  }

  # return decoded response
  return $response->decoded_content;
}

sub execute_slack {
  my $self = shift;

  my %params;
  my $wait;

  my $json;
  if (ref($_[0]) eq 'HASH') {
    %params = %{+shift};
    $wait = shift;
  } elsif (ref($_[0]) eq 'ARRAY') {
    (%params) = @{+shift};
    $wait = shift;
  } elsif (ref($_[0]) eq 'SCALAR') {
    $json = ${+shift};
  } elsif (scalar @_ > 1) {
    (%params) = @_;
  } else {
    $json = shift;
  }

  if (!defined $wait && %params) { $wait = delete $params{wait} }
  if (!defined $json) { $json = encode_json(\%params) }

  # create a slack-format post url
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token} . '/slack';
  if ($wait) { $url .= '?wait=true' }

  my $response = $self->{ua}->post($url, Content => $json, 'Content-Type' => 'application/json');
  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->post($url) returned: " . $response->status_line . " (" . $response->decoded_content . ")";
    return undef;
  }

  # return decoded response
  return $response->decoded_content;
}

sub execute_github {
  my $self = shift;

  my %params;
  my $github_event;
  my $wait;

  if (ref($_[0]) eq 'HASH') {
    %params = %{+shift};
    $github_event = shift;
    $wait = shift;
  } elsif (ref($_[0]) eq 'ARRAY') {
    (%params) = @{+shift};
    $github_event = shift;
    $wait = shift;
  } else {
    (%params) = @_;
  }

  if (!defined $github_event) {
    $github_event = delete $params{wait};
    if (!defined $github_event) {
      croak "execute_github() requires github_event parameter";
    }
  }
  if (!defined $wait) { $wait = delete $params{wait} }

  # create a github-format post url
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token} . '/github';
  if ($wait) { $url .= '?wait=true' }

  my $response = $self->{ua}->post($url, Content => encode_json(\%params), 'Content-Type' => 'application/json', 'X-GitHub-Event' => $github_event);
  if ( ! $response->is_success ) {
    carp "Warning: LWP::UserAgent->post($url) returned: " . $response->status_line . " (" . $response->decoded_content . ")";
    return undef;
  }

  # return decoded response
  return $response->decoded_content;
}

1;

__END__

=pod

=head1 NAME

Net::Discord::Webhook - A module for posting messages to Discord chat service

=head1 SYNOPSIS

    use Net::Discord::Webhook;

    my $webhook = Net::Discord::Webhook( $url );

    $webhook->execute( { content => 'Hello, world!' } );

    sleep(30);

    $webhook->execute( 'Goodbye, world!' );

=head1 DESCRIPTION

This module posts messages to the Discord chat service, using their Webhook
interface.  Webhooks are a simple way to add post-only functions to external
clients, without the need to create a full-fledged client or "bot".

Normally, Webhooks are used to issue a notification to chat channels when an
external event from another site or service occurs, e.g. when a commit is made
to a Git repository, a story is posted to a news site, or a player is fragged
in a game.

An example Discord Webhook URL looks like this:

    https://discordapp.com/api/webhooks/2237...5344/3d89...cf11

where the first magic number ("2237...5344") is the C<id> and the second
("3d89...cf11") is the C<token>.

For more information on Discord Webhooks, see the Discord API documentation
located at L<https://discordapp.com/developers/docs/resources/webhook>.

=head2 Methods

=over 12

=item C<new>

Constructs and returns a new Net::Discord::Webhook object using the specified
parameters.

This function should be passed a hash reference, containing either a C<url>
key, or C<token> plus C<id> keys, with values matching the Webhook created
via the Discord UI.

An optional parameter C<timeout> can be used to override the default timeout
of the underlying L<LWP::UserAgent> object used for making web requests.

As a special case, if C<new> is called with a scalar parameter, it is assumed
to be a C<url>.

=item C<get>

Retrieves server-side information for the Webhook, and caches the result
in the Net::Discord::Webhook object.  No parameters are expected.

Information which can be returned from the remote service include:
* guild_id: The guild ("server") which the Webhook currently posts to, if set
* channel_id: The specific channel which the Webhook posts to
* name: The current display name of the Webhook
* avatar: A URL pointing to the current avatar used by the Webhook

A hash containing the data is returned.  Additionally, the hash values are
copied into the object itself, so they can be later retrieved by calling code
(as in C<$webhook-E<gt>{channel_id}>).

=item C<modify>

Modifies the server-side information for the Webhook.  This can be used to
alter the name the Webhook uses, the avatar, or both.

=item C<delete>

Deletes the Webhook from the Discord service.

B<Warning!>  Once a Webhook is deleted, the existing token and ID are no
longer valid.  A server administrator will need to re-create the endpoint
through the Discord UI.  Unless you have very good reason to do this, it is
probably best to leave this function alone.

=item C<execute>

Executes a Webhook (posts a message).

=item C<execute_slack>

Executes a Slack-compatible Webhook.

=item C<execute_github>

Executes a Github-compatible Webhook.

=back

=head1 LICENSE

This is released under the Artistic License. See L<perlartistic>.

=head1 AUTHOR

Greg Kennedy - L<https://greg-kennedy.com/>

=cut
