use strict;
use warnings;

# Perl Webhook test client
#  Greg Kennedy 2019
use Test::More;

use Net::Discord::Webhook;
use JSON::PP qw(decode_json);
use Getopt::Long;

my $url;
GetOptions( "url=s"   => \$url ) or BAIL_OUT("Error in command line arguments.");
if (!defined $url) { BAIL_OUT( "Error: --url is required: try running with `prove -b xt :: --url <discord_webhook_url>`" ) }

#####################

## CONSTRUCTOR
# Create webhook client object
my $webhook;
ok( $webhook = Net::Discord::Webhook->new(url => $url, wait => 1), "Create webhook object" );

## GET
# Get data
ok( $webhook->get(), "GET method" );

## MODIFY
# go change my name and avatar
open my $fp, '<:raw', 'xt/data/mandrill.png' or die $!;
read $fp, my $image, -s 'xt/data/mandrill.png';
close $fp;

ok( $webhook->modify( name => "Webhook Test", avatar => $image ), "PATCH method - new name and avatar" );
#ok( $webhook->modify( avatar => undef ), "PATCH method" );
is( $webhook->{name}, 'Webhook Test', 'Name change OK' );
ok( ! $webhook->modify("A" x 256), "PATCH method - name too long" );

## EXECUTE
# try a TTS message post
isa_ok( $webhook->execute( content => "This is a Webhook Test!", tts => 1 ), 'HASH', 'execute method' );

# post a file
isa_ok( $webhook->execute( username => 'FileUploadTest', content => 'Monkey see, monkey do!', file => { name => 'monkey.png', data => $image } ), 'HASH', 'file upload' );

# try embed
my $embed = decode_json('{
    "title": "title ~~(did you know you can have markdown here too?)~~",
    "description": "this supports [named links](https://discordapp.com) on top of the previously shown subset of markdown. ```\nyes, even code blocks```",
    "url": "https://discordapp.com",
    "color": 3491017,
    "timestamp": "2019-09-02T07:43:25.448Z",
    "footer": {
      "icon_url": "https://cdn.discordapp.com/embed/avatars/0.png",
      "text": "footer text"
    },
    "thumbnail": {
      "url": "https://cdn.discordapp.com/embed/avatars/0.png"
    },
    "image": {
      "url": "https://cdn.discordapp.com/embed/avatars/0.png"
    },
    "author": {
      "name": "author name",
      "url": "https://discordapp.com",
      "icon_url": "https://cdn.discordapp.com/embed/avatars/0.png"
    },
    "fields": [
      {
        "name": "🤔",
        "value": "some of these properties have certain limits..."
      },
      {
        "name": "😱",
        "value": "try exceeding some of them!"
      },
      {
        "name": "🙄",
        "value": "an informative error should show up, and this view will remain as-is until all issues are fixed"
      },
      {
        "name": "<:thonkang:219069250692841473>",
        "value": "these last two",
        "inline": true
      },
      {
        "name": "<:thonkang:219069250692841473>",
        "value": "are inline fields",
        "inline": true
      }
    ]
}');
isa_ok( $webhook->execute( embed => $embed ), 'HASH', 'Embed' );

# message too long
ok( ! $webhook->execute("A" x 4096), "EXECUTE method - message too long" );

## EXECUTE_GITHUB
# send github hook
open $fp, '<:encoding(UTF-8)', 'xt/data/github-pull-request.json' or die $!;
my $json = do { local $/; <$fp> };
close $fp;

ok( $webhook->execute_github( event => 'pull_request', json => $json ), "execute_github method" );

## EXECUTE_SLACK
# send slack hook
is( $webhook->execute_slack('{"text":"This is the Slack endpoint."}'), 'ok', "execute_slack method" );

done_testing();
