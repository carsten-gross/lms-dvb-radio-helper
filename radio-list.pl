#! /usr/bin/perl -w

use strict;
use LWP::UserAgent;
use REST::Client;
use JSON;
# Data::Dumper makes it easy to see what the JSON returned actually looks like 
# when converted into Perl data structures.
use Data::Dumper;
use MIME::Base64;
use URI::Encode qw(uri_encode);
use utf8;
# Enforce UTF-8 (perhaps it's wrong on console but this avoids problems with 
#	 the encoding when used as CGI 
use open OUT=>':utf8';

# Yes, yes, yes, CGI is outdated but best to use for this 
# kind of applications (stateless & simple output) 
use CGI::Carp qw(warningsToBrowser fatalsToBrowser); 

# User & Password for your tvheadend installation
my $username = 'tv';
my $password = 'gucken';
my $Basehost = 'tvheadend.example.com';

# I've tvheadend, the apache and LMS running on the same host. Change 
# URLs as needed
# TV Headend base URL
my $TVHeadendBase = $Basehost . ":9981"; 
# URL for ts2shout
my $RadioURL = "http://" . $Basehost . "/radio"; 
# URL for station-list (this script)
my $StationURL = "http://" . $Basehost . "/station"; 

#######################################################
# (Nearly) no user configurable stuff below this point 
#######################################################

my $ua = LWP::UserAgent->new();
$ua->credentials($TVHeadendBase , 'tvheadend', $username, $password ); 
# We've to follow redirects otherwise Digest Authentication won't work
my $client = REST::Client->new({ useragent => $ua, follow => 1 });
# We want to talk to our tvheadend-Server
$client->setHost($TVHeadendBase);

# Get Channel-Tag Assignement from tvheadend
$client->GET( '/api/channeltag/grid?limit=5000');

if ($client->responseCode() > 200 ) {
	print STDERR $client->responseContent() . "\n";
	die "Error " . $client->responseCode() . " connecting to " . $TVHeadendBase . "/api/channeltag/grid\n"; 
}
my $json = decode_json($client->responseContent());

my $tags = $json->{'entries'}; 
# print Dumper($tags);
my %tvtag;
my %tvicon; 
my $radiotag; 
# Fetch the tvheadend ids for the channel-tag names. 
# Special handling for the "Radio" Tag
foreach my $elem (@{$tags}) {
	# print Dumper($elem);
	# "grid" method has other values than "list"
	my $key = $$elem{'uuid'};
	my $val = $$elem{'name'};
	my $icon = $$elem{'icon_public_url'};
	if (defined $icon && length($icon) > 1) {
		# Nur setzen wenn es da ist
		$tvicon{$key} = "http://" . $TVHeadendBase . "/" . $icon;
	}
	$tvtag{$key} = $val;
	if ($val eq 'Radio') {
		$radiotag = $key; 
	}
}
# Get Full Channel-List with Tags
$client->GET('/api/channel/grid?limit=2000'); 
if ($client->responseCode() > 200 ) {
	print STDERR $client->responseContent() . "\n";
	die "Error " . $client->responseCode() . " connecting to " . $TVHeadendBase . "/api/channel/grid\n"; 
}
$json = decode_json($client->responseContent());

$tags = $json->{'entries'}; 
my %station; 
my $found_radio = 0;
my @RadioList; 
foreach my $elem (@{$tags}) {
	# print Dumper($elem); 
	my @L;
	my @UL;
	my @SL;
	my @SUL;
	if (! $elem->{'enabled'}) {
		next;
	}
	if (defined $elem && defined $elem->{'tags'}) {
		# print Dumper($elem->{'tags'});
		foreach my $key (@{$elem->{'tags'}}) {
			if ($key eq $radiotag) {
				$found_radio = 1;
			} else {
				push @L, $tvtag{$key};
				push @UL, $key; 
			}
			@SL = sort(@L); 
			@SUL = sort(@UL); 
		}
	}
	# Put user printable list of tags into "tvtags"
	# but only add stations tagged with "Radio" to our hash of possible
	# stations. 
	$elem->{'tvtags'} = \@SL;
	if ($found_radio) {
		my %S; 
		$S{'name'} = $elem->{'name'}; 
		$S{'tags'} = $elem->{'tvtags'}; 
		$S{'uuidtags'} = \@SUL;
		$S{'url'} = $RadioURL . "/" . uri_encode($elem->{'name'});
		$S{'icon'} = "http://" . $TVHeadendBase . "/" . $elem->{'icon_public_url'}; 
		$S{'number'} = $elem->{'number'};
		push @RadioList, \%S;
	}
	$found_radio = 0;
}

# Prepare the full output xml/opml string
my $output; 

# This is set by webserver serving us (e.g. apache)
my $match = $ENV{'PROGRAMMNO'}; 
if (! defined $match) {
	$match = $ENV{'REDIRECT_PROGRAMMNO'}; 
}
if (defined $match) {
	$match =~ s/([-A-Za-z0-9_ ]*)$/$1/; 
}
if (! defined $match) {
	$match = ""; 
}


# XML Header
$output = <<PAGE_START;
<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0">
  <head title="$match">
    <expansionState></expansionState>
  </head>
  <body>
PAGE_START

# The wanted output for the opml list should look like this
# Directories
# <outline URL="http://localhost/station/" icon="html/images/favorites.png" text="Alle Radioprogramme" type="playlist" />
# Radio-Station Entries
# <outline url="http://localhost/radio/NDR 1" image="http://localhost/logos/NDR1.png" text="NDR 1 Nieders." type="audio" />

# Tag the Channels in "Channel/EPG -> Channel Tags" in tvheadend Dialog with an "Icon" 
my $LE = ""; # LE Last entry

if (defined $match && length($match) > 1) {
	foreach my $elem ( sort { $a->{'number'} <=> $b->{'number'} }  @RadioList) {
		# A matching string is given
		if ( join(",", @{$elem->{'tags'}}) eq $match ) {
			$output .= qq|	<outline url="| . $elem->{'url'} . qq|" image="| . $elem->{'icon'} . qq|" text="| . $elem->{'name'} . qq|" type="audio" />\n|; 
		}
	}
} else {
	foreach my $elem ( sort { join(",", @{$a->{'tags'}}) cmp join(",", @{$b->{'tags'}}) } @RadioList) {
		my $entry = join(",", @{$elem->{'tags'}});
		my $uuidentry = join(",", @{$elem->{'uuidtags'}}); 
		if (! defined $entry || length($entry) < 1) {
			$output .= qq|  <outline url="| . $elem->{'url'} . qq|" image="| . $elem->{'icon'} . qq|" text="| . $elem->{'name'} . qq|" type="audio" />\n|;
		} else {
			if ($entry ne $LE) {
				$output .= qq|	<outline url="| . $StationURL . "/" . $entry; 
				if (defined $tvicon{$uuidentry}) {
					$output .= qq|" icon="| .$tvicon{$uuidentry} . qq|" |;
				} else {
					$output .= qq|" icon="html/images/favorites.png"|; 
				}
				$output .= qq| text="| . $entry . qq|" type="playlist" />\n|; 
				$LE = $entry; 
			}
		}
	}
}
$output .= <<PAGE_END;
  </body>
</opml>
PAGE_END

print "Content-Length: " . length($output) . "\n";
print "Content-Type: text/xml; charset=utf-8\n\n"; 
print $output; 

exit(0);
