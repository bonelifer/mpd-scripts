#!/usr/bin/perl

# Fetches iHeartRadio station URLs and generates M3U playlists
# along with associated station information, including titles,
# stream URLs, and optional station images. Utilizes StreamFinder::IHeartRadio
# Perl module for data retrieval and saves data in a 'playlists' directory.
# Station URLs are read from stations.txt (see --stations) so the list can
# be edited without touching this script.
# Requires LWP::Simple and File::Path modules for downloading images
# and managing directories.

# To install required Perl modules:
# 1. Install cpanm (CPAN Minus) using apt:
#    sudo apt update
#    sudo apt install cpanminus
#
# 2. Install StreamFinder::IHeartRadio, LWP::Simple, and File::Path using cpanm:
#    sudo cpanm StreamFinder::IHeartRadio LWP::Simple File::Path

use strict;
use warnings;
use FindBin qw($RealBin);
use Getopt::Long;
use StreamFinder::IHeartRadio;  # Fetch iHeartRadio station details
use LWP::Simple;               # For downloading station images
use File::Path qw(make_path);   # For managing directories

# iheart.com intermittently serves a page without the embedded stream data,
# so a station lookup that fails once may succeed on a retry.
use constant RETRY_DELAY_SECONDS => 3;

my $USAGE = <<"EOF";
Usage: $0 -d [--skip-existing|-s] [--retries|-r N] [--stations|-f FILE]

  -d, --download        Fetch stations and write playlists/images (required; nothing else does this)
  -s, --skip-existing    Skip stations already completed in a prior run
  -r, --retries N        Attempts per station before giving up (default: 3)
  -f, --stations FILE    Station list file (default: stations.txt next to this script)
EOF

# With --skip-existing, stations already completed in a prior run are left
# untouched instead of being re-fetched, so the script can be re-run as many
# times as needed to pick up the stations iheart.com failed on previously.
# --retries overrides how many attempts each station gets (default: 3).
# --stations points at the station list file (default: stations.txt next to this script).
# --download is required to actually run; with no arguments (or without
# --download), the script just prints usage and exits.
my $skipExisting = 0;
my $maxAttempts = 3;
my $stationsFile = "$RealBin/stations.txt";
my $download = 0;
GetOptions(
    'skip-existing|s' => \$skipExisting,
    'retries|r=i'     => \$maxAttempts,
    'stations|f=s'    => \$stationsFile,
    'download|d'      => \$download,
) or die $USAGE;
die "--retries must be a positive integer\n" unless $maxAttempts > 0;

unless ($download) {
    print $USAGE;
    exit 0;
}

my $playlistDir = "./playlists";  # Directory to store playlists
make_path($playlistDir);

my $completedDir = "$playlistDir/.completed";  # Marker files recording finished stations
make_path($completedDir);

open my $stations_fh, '<', $stationsFile or die "Cannot open stations file $stationsFile: $!\n";
my @stations;
while (my $line = <$stations_fh>) {
    $line =~ s/^\s+|\s+$//g;  # Trim whitespace
    next if $line eq '' || $line =~ /^#/;  # Skip blank lines and comments

    # Optional "URL,custom-name" — custom-name overrides the derived-from-title
    # filename below; leave it blank (or omit the comma) to keep that behavior.
    my ($url, $customName) = split /\s*,\s*/, $line, 2;
    push @stations, [$url, $customName];
}
close $stations_fh;

die "No station URLs found in $stationsFile\n" unless @stations;

foreach my $stationEntry (@stations) {
    my ($stationURL, $customName) = @$stationEntry;
    # Stable per-station identifier (last URL path segment) used only for the
    # completion marker below; the full URL is still what's passed to the module.
    (my $urlNoSlash = $stationURL) =~ s{/+$}{};
    my ($stationID) = $urlNoSlash =~ m{([^/]+)$};
    my $markerFile = "$completedDir/$stationID.done";

    if ($skipExisting && -e $markerFile) {
        print "Skipping $stationURL (already completed in a previous run)\n";
        next;
    }

    # StreamFinder::IHeartRadio extracts the station ID from a full URL itself,
    # so pass it straight through rather than re-parsing it here.
    my $station;
    for my $attempt (1 .. $maxAttempts) {
        $station = StreamFinder::IHeartRadio->new($stationURL, -keep => ['secure_shoutcast', 'secure', 'any'], -skip => 'rtmp');
        last if $station;

        if ($attempt < $maxAttempts) {
            warn "Attempt $attempt/$maxAttempts failed for $stationURL, retrying in @{[RETRY_DELAY_SECONDS]}s...\n";
            sleep RETRY_DELAY_SECONDS;
        }
    }

    unless ($station) {
        warn "Invalid URL or no streams found for $stationURL after $maxAttempts attempts\n";
        next;
    }

    my $stationTitle = $station->getTitle();  # Fetch station title/name

    # A custom name from stations.txt overrides the derived-from-title filename;
    # otherwise fall back to the station's title, same as before.
    my $filenameBase = (defined $customName && $customName ne '') ? $customName : $stationTitle;

    # Remove unwanted characters from the name to use as playlist and image filenames
    my $safeFilename = $filenameBase =~ s/[^\w.-]+/_/gr;

    my $playlistFilename = "$playlistDir/$safeFilename.m3u";  # Set playlist filename using station name within the directory
    my $imageFilename = "$playlistDir/$safeFilename.png";  # Set image filename using station name within the directory

    my $firstStream = $station->getURL();
    my $imageURL = $station->getImageURL();

    if ($imageURL) {
        my $imageData = get($imageURL);

        if ($imageData) {
            open my $image_fh, '>', $imageFilename or die "Cannot create image file: $!";
            binmode $image_fh;
            print $image_fh $imageData;
            close $image_fh;

            print "Station image downloaded to $imageFilename\n";
        }
    } else {
        print "No image found for $stationTitle\n";
    }

    open my $playlist_fh, '>', $playlistFilename or die "Cannot create playlist file: $!";

    print $playlist_fh "#EXTM3U\n";
    print $playlist_fh "#EXTINF:-1,$stationTitle\n";
    print $playlist_fh "#EXTIMG:$safeFilename.png\n" if -e $imageFilename; # Include image if available
    print $playlist_fh "$firstStream\n";

    close $playlist_fh;

    print "Playlist created for $playlistFilename\n";

    open my $marker_fh, '>', $markerFile or warn "Cannot create marker file $markerFile: $!\n";
    close $marker_fh if $marker_fh;
}

