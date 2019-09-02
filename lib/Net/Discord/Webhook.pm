package Net::Discord::Webhook;

use strict;
use warnings;

# Module for interacting with the REST service
use HTTP::Tiny;
# JSON decode
use JSON::PP qw(encode_json decode_json);
# Base64 encode for avatar images
use MIME::Base64 qw(encode_base64);
# better error messages
use Carp qw(croak carp);
# Parse filename from filepath
use File::Spec;

# PACKAGE VARS
our $VERSION = '1.00';

# Base URL for all API requests
our $BASE_URL = 'https://discordapp.com/api';

##################################################

# Create a new Webhook object.
#  Pass a hash containing parameters
#  Requires:
#   url, or
#   token and id
#  Optional:
#   wait
#   timeout
#   verify_SSL
#  A single scalar is treated as a URL
sub new
{
  my $class = shift;

  my %params;
  if (scalar @_ > 1) {
    %params = @_;
  } else {
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
  my %attributes = ( agent => 'p5-Net-Discord-Webhook (https://github.com/greg-kennedy/p5-Net-Discord-Webhook, ' . $VERSION . ')' );
  if ($params{timeout}) { $attributes{timeout} = $params{timeout} }
  if ($params{verify_SSL}) { $attributes{verify_SSL} = $params{verify_SSL} }

  my $http = HTTP::Tiny->new( %attributes );

  # create class with some params
  my $self = bless { id => $id, token => $token, http => $http }, $class;
  if ($params{wait}) { $self->{wait} = 1 }

  # call get to populate additional details
  #$self->get();

  return $self;
}

# updates internal structures after a webhook request
sub _parse_response {
  my $self = shift;
  my $json = shift;

  my $response = decode_json($json);

  # sanity
  if ($self->{id} ne $response->{id}) {
    carp "Warning: get() returned ID='" . $response->{id} . "', expected ID='" . $self->{id} . "'"
  }
  if ($self->{token} ne $response->{token}) {
    carp "Warning: get() returned Token='" . $response->{token} . "', expected Token='" . $self->{token} . "'"
  }

  # store / update details
  if (exists $response->{guild_id}) {
    $self->{guild_id} = $response->{guild_id}
  } else {
    delete $self->{guild_id}
  }
  $self->{channel_id} = $response->{channel_id};
  $self->{name} = $response->{name};
  $self->{avatar} = $response->{avatar};

  return $response;
}

# GET request
#  Retrieves some info about the webhook setup
#  No parameters
sub get {
  my $self = shift;

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};

  my $response = $self->{http}->get($url);
  if ( ! $response->{success} ) {
    # non-200 code returned
    carp "Warning: HTTP::Tiny->get($url) returned error (" . $response->{status} . " " . $response->{reason} . "): '" . $response->{content} . "'";
    return;
  } elsif (! $response->{content}) {
    # empty result
    carp "Warning: HTTP::Tiny->get($url) returned empty response (" . $response->{status} . " " . $response->{reason} . ")";
    return;
  }

  # update internal structs and return
  return $self->_parse_response($response->{content});
}

# PATCH request
#  Allows webhook to alter its Name or Avatar
sub modify {
  my $self = shift;

  my %params;
  if (scalar @_ > 1) {
    %params = @_;
  } else {
    $params{name} = shift;
  }

  my %request;

  # retrieve the two allowed params and place in request if needed
  if (defined $params{name}) { $request{name} = $params{name} }

  if (exists $params{avatar}) {
    if (defined $params{avatar}) {
      # try to infer type from data string
      my $type;
      if (substr($params{avatar}, 0, 8) eq "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a") {
        $type = 'image/png';
      } elsif (substr($params{avatar}, 0, 2) eq "\xff\xd8" && substr($params{avatar}, -2) eq "\xff\xd9") {
        $type = 'image/jpeg';
      } elsif (substr($params{avatar}, 0, 4) eq 'GIF8') {
        $type = 'image/gif';
      } else {
        carp "Could not determine image type from data";
        return;
      }
  
      $request{avatar} = 'data:' . $type . ';base64,' . encode_base64($params{avatar});
    } else {
      $request{avatar} = undef;
    }
  }

  if (! %request) {
    carp "Modify request with no valid parameters";
    return;
  }

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};

  # PATCH method not yet built-in as of 0.076
  #my $response = $self->{http}->patch($url, \%request);
  my $response = $self->{http}->request('PATCH', $url, { headers => { 'Content-Type' => 'application/json' }, content => encode_json(\%request) } );
  if ( ! $response->{success} ) {
    # non-200 code returned
    carp "Warning: HTTP::Tiny->patch($url) returned error (" . $response->{status} . " " . $response->{reason} . "): '" . $response->{content} . "'";
    return;
  } elsif (! $response->{content}) {
    # empty result
    carp "Warning: HTTP::Tiny->patch($url) returned empty response (" . $response->{status} . " " . $response->{reason} . ")";
    return;
  }

  # update internal structs and return
  return $self->_parse_response($response->{content});
}

# DELETE request - deletes the webhook
sub delete {
  my $self = shift;

  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};

  my $response = $self->{http}->delete($url);
  if ( ! $response->{success} ) {
    carp "Warning: HTTP::Tiny->delete($url) returned error (" . $response->{status} . " " . $response->{reason} . "): '" . $response->{content} . "'";
    return;
  }

  # DELETE response is 204 NO CONTENT, simply return true if successful.
  return 1;
}

# EXECUTE - posts the message.
# Required parameters: one of
#  content
#  file and/or filename
#  embed or embeds
# Optional paremeters:
#  username
#  avatar_url
#  tts
sub execute {
  my $self = shift;

  # extract params
  my %params;
  if (scalar @_ > 1) {
    %params = @_;
  } else {
    $params{content} = shift;
  }

  # compose URL
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token};
  if ($self->{wait}) { $url .= '?wait=true' }

  # test required fields
  if (! ($params{content} || $params{embed} || $params{embeds} || $params{file} || $params{filename}) )
  {
    carp "Execute request missing required parameters (must have at least content, embeds or file)";
    return;
  } elsif ( ($params{embed} || $params{embeds}) && ($params{file} || $params{filename}) )
  {
    carp "Execute request: cannot combine file and embeds request in one call.";
    return;
  }

  # construct JSON request
  my %request;

  # all messages types may have these params
  if ($params{content}) { $request{content} = $params{content} }

  if (defined $params{username}) { $request{username} = $params{username} }
  if (defined $params{avatar_url}) { $request{avatar_url} = $params{avatar_url} }
  if ($params{tts}) { $request{tts} = JSON::PP::true }

  # switch mode for request based on file upload or no
  my $response;
  if (! ($params{file} || $params{filename})) {
    # This is a regular, no-fuss JSON request
    if ($params{embeds}) { $request{embeds} = $params{embeds} }
    elsif ($params{embed}) { $request{embeds} = [ $params{embed} ] }

    $response = $self->{http}->post($url, { headers => { 'Content-Type' => 'application/json' }, content => encode_json(\%request) } );
  } else {
    # File upload
    my $file;
    my $filename;

    # did not provide a file - we need to open it from disk
    if (! $params{file}) {
      # go change my name and avatar
      my $size = -s $params{filename};
      open(my $fp, '<:raw', $params{filename}) or die $!;
      read $fp, $file, $size;
      close $fp;

      # set filename to basename(filename)
      $filename = (File::Spec->splitpath( $params{filename} ))[2];
    } elsif (! $params{filename}) {
      $file = $params{file};
      $filename = 'unknown.bin';
    } else {
      # they provided both
      $file = $params{file};
      $filename = (File::Spec->splitpath( $params{filename} ))[2];
    }

    # Construct a multipart/form-data message
    my @chars = ('A' .. 'Z', 'a' .. 'z', '0' .. '9');
    my $boundary = '';
    for (my $i = 0; $i < 16; $i ++) {
      $boundary .= $chars[rand @chars];
    }

    my $content = '';
    $content .= "\r\n--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"file1\"; filename=\"$filename\"\r\n";
# Discord ignores content-type
  #  $content .= "Content-Type: $type\r\n";
    $content .= "\r\n";
    $content .= $params{file} . "\r\n";

    $content .= "\r\n--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"payload_json\";\r\n";
    $content .= "Content-Type: application/json\r\n";
    $content .= "\r\n";
    $content .= encode_json(\%request) . "\r\n";

    $content .= "\r\n--$boundary--\r\n";

    $response = $self->{http}->post($url, {
      headers => {'Content-Type' => "multipart/form-data; boundary=$boundary"},
      content => $content
    });
  }

  if ( ! $response->{success} ) {
    carp "Warning: HTTP::Tiny->post($url) returned: " . $response->{status} . " " . $response->{reason} . ": '" . $response->{content} . "'";
    return;
  }

  # return details
  return $response->{content};
}

sub execute_slack {
  my $self = shift;

  my $json;
  if (scalar @_ > 1) {
    my %params = @_;
    $json = encode_json(\%params);
  } else {
    $json = shift;
  }

  # create a slack-format post url
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token} . '/slack';
  if ($self->{wait}) { $url .= '?wait=true' }

  my $response = $self->{http}->post($url, { headers => { 'Content-Type' => 'application/json' }, content => $json } );
  if ( ! $response->{success} ) {
    carp "Warning: HTTP::Tiny->post($url) returned: " . $response->{status} . " " . $response->{reason} . ": '" . $response->{content} . "'";
    return;
  }

  # return details
  return $response->{content};
}

sub execute_github {
  my $self = shift;

  my %params;
  my $github_event;

  %params = @_;

  $github_event = delete $params{github_event};
  if (!defined $github_event) {
    croak "execute_github() requires github_event parameter";
  }

  # create a github-format post url
  my $url = $BASE_URL . '/webhooks/' . $self->{id} . '/' . $self->{token} . '/github';
  if ($self->{wait}) { $url .= '?wait=true' }

  my $response = $self->{http}->post($url, { headers => { 'Content-Type' => 'application/json', 'X-GitHub-Event' => $github_event }, content => encode_json(\%params) } );
  if ( ! $response->{success} ) {
    carp "Warning: HTTP::Tiny->post($url) returned: " . $response->{status} . " " . $response->{reason} . ": '" . $response->{content} . "'";
    return;
  }

  # return details
  return $response->{content};
}

1;

__END__

=pod

=head1 NAME

Net::Discord::Webhook - A module for posting messages to Discord chat service

=head1 VERSION

version 1.00

=head1 SYNOPSIS

    use Net::Discord::Webhook;

    my $webhook = Net::Discord::Webhook( $url );

    $webhook->get();
    print "Webhook posting as '" . $webhook->{name} .
      "' in channel " . $webhook->{channel_id} . "\n";

    $webhook->execute( content => 'Hello, world!', tts => 1 );

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

=head1 METHODS

=head2 new

Constructs and returns a new Net::Discord::Webhook object using the specified
parameters.

This function should be passed a hash, containing either a C<url>
key, or C<token> plus C<id> keys, with values matching the Webhook created
via the Discord UI.

The following optional parameters are also available:

=over

=item * timeout

Override the default timeout of the underlying L<HTTP::Tiny> object used for
making web requests.

=item * verify_SSL

Enable SSL certificate verification on the underlying L<HTTP::Tiny> object.
Note that this will probably require a trusted CA certificate list installed.

=item * wait

Webhook execution will block before returning, until the server confirms that
he message was sent.  By default this is disabled (webhook execution is NOT
synchronized), so the function may return success although a message does not
actually post.

=back

As a special case, if C<new> is called with a scalar parameter, it is assumed
to be a C<url>.

=head2 get

Retrieves server-side information for the Webhook, and caches the result
in the Net::Discord::Webhook object.  No parameters are expected.

Information which can be returned from the remote service include:

=over

=item * guild_id:
The guild ("server") which the Webhook currently posts to, if set

=item * channel_id:
The specific channel which the Webhook posts to

=item * name:
The current display name of the Webhook

=item * avatar:
A URL pointing to the current avatar used by the Webhook

=back

A hash containing the data is returned.  Additionally, the hash values are
copied into the object itself, so they can be later retrieved by calling code
(as in C<$webhook-E<gt>{channel_id}>).

=head2 modify

Modifies the server-side information for the Webhook.  This can be used to
alter the name the Webhook uses, the avatar, or both.

This function should be passed a hash, containing (at least) a
C<name> key or C<avatar> key (or both).

For C<avatar>, the value should be the raw data bytes of a png, jpeg, or gif
image.

As a special case, if C<modify> is called with a scalar parameter, it is assumed
to be a new username.

The return value for this function is the same as C<get>, and the results
are also cached as above.

=head2 delete

Deletes the Webhook from the Discord service.  Returns True if successful,
undef otherwise.

B<Warning!>  Once a Webhook is deleted, the existing token and ID are no
longer valid.  A server administrator will need to re-create the endpoint
through the Discord UI.  Unless you have very good reason to do this, it is
probably best to leave this function alone.

=head2 execute

Executes a Webhook (posts a message).

The function should be passed a hash containing a Discord webhook
structure.  Discord allows several different methods to post to a channel.
At least one of the following components is required:

=over

=item * content

Post a plain-text message to the channel.  The message can be up to 2000
Unicode characters in length.

The value should be a scalar containing the message to post.

=item * file

Upload a file to the channel.

The value should be a scalar containing the raw data bytes of the file.

=item * embeds

Post "embedded rich content" to the channel.  This is useful for posting
messages with image attachments, colorful borders or backgrounds, etc.

The value should be an array of embed objects to post.  These values are
not checked by Net::Discord::Webhook.  For information on the expected
data structure, refer to Discord's documentation on Channel Embed Objects:
L<https://discordapp.com/developers/docs/resources/channel#embed-object>

=back

Additionally, these optional parameters can be used to change the behavior
of the webhook:

=over

=item * username:
Override the default username of the webhook (i.e. post this message under a
different name).  To make a permanent username change, see C<modify>.

=item * avatar_url:
Override the default avatar of the webhook (i.e. post this message using the
avatar at avatar_url).  To upload a new avatar to Discord, see C<modify>.

=item * tts:
If set, posts as a TTS message.  TTS messages appear as normal, but will also
be read aloud to users in the channel (if permissions allow).

=back

As a special case, if a scalar is passed to this function, it is assumed to
be a plain-text message to post via the "content" method.

The return value for this function depends on the setting of C<wait> during
webhook construction.  If C<wait> is False (default), the function returns
immediately: parameters are checked for validity, but no attempt is made to
verify that the message actually posted to the channel.  If C<wait> is True,
function return is delayed until the message successfully posts.  The return
value in this case is the contents of the posted message.

=head2 execute_slack

Executes a Slack-compatible Webhook.

The function should be passed either a scalar (assumed to be the JSON string
contents of the Slack webhook), or a hash containing a Slack webhook
structure (will be encoded to JSON using C<JSON::PP>).

More information about the format of a Slack webhook is available on the
Slack API reference at L<https://api.slack.com/incoming-webhooks>.

This function's return value is similar to that of C<execute> (above).

=head2 execute_github

Executes a Github-compatible Webhook.

The function should be passed either a scalar (assumed to be the JSON string
contents of the Github webhook), or a hash containing a Slack webhook
structure (will be encoded to JSON using C<JSON::PP>).

More information about the format of a Github webhook is available on the
Github API reference at L<https://developer.github.com/webhooks>.

B<Note:>  Posting a message using the C<execute_github> function is currently
a specially-cased feature of Discord.  The webhook always appears as a user
named "GitHub" with a custom avatar, ignoring any existing styling.  Thus it
should NOT be used as a general-purpose posting function.  However, it may be
useful to proxy messages from GitHub and repost them on Discord.

This function's return value is similar to that of C<execute> (above).

=head1 LICENSE

This is released under the Artistic License. See L<perlartistic>.

=head1 AUTHOR

Greg Kennedy - L<https://greg-kennedy.com/>

=cut
