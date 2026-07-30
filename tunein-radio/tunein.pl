#!/usr/bin/perl

# Fetches TuneIn radio station URLs and generates M3U playlists
# with associated station information including titles, stream URLs,
# and optional station images. Utilizes StreamFinder::Tunein Perl
# module for data retrieval and saves data in a 'playlists' directory.
# Station URLs are read from stations.txt (see --stations) so the list
# can be edited without touching this script.
# Requires LWP::Simple module for image downloading.

# To install required Perl modules:
# 1. Install cpanm (CPAN Minus) using apt:
#    sudo apt update
#    sudo apt install cpanminus
#
# 2. Install StreamFinder::Tunein and LWP::Simple using cpanm:
#    sudo cpanm StreamFinder::Tunein LWP::Simple

use strict;
use warnings;
use FindBin qw($RealBin);
use Getopt::Long;
use StreamFinder::Tunein;  # Fetch TuneIn station details
use LWP::Simple;          # For downloading station images

# tunein.com can intermittently fail to resolve a valid station, so a
# lookup that fails once may succeed on a retry.
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
# times as needed to pick up any stations that failed previously.
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

# Create playlists directory if it doesn't exist
my $playlistDir = 'playlists';
unless (-e $playlistDir && -d $playlistDir) {
    mkdir $playlistDir or die "Unable to create directory: $!";
}

my $completedDir = "$playlistDir/.completed";  # Marker files recording finished stations
unless (-e $completedDir && -d $completedDir) {
    mkdir $completedDir or die "Unable to create directory: $!";
}

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

# Iterate through each station and fetch station images and generate M3U playlists
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

    my $station_obj;
    for my $attempt (1 .. $maxAttempts) {
        $station_obj = StreamFinder::Tunein->new($stationURL);
        last if $station_obj;

        if ($attempt < $maxAttempts) {
            warn "Attempt $attempt/$maxAttempts failed for $stationURL, retrying in @{[RETRY_DELAY_SECONDS]}s...\n";
            sleep RETRY_DELAY_SECONDS;
        }
    }

    unless ($station_obj) {
        warn "Invalid URL or no streams found for $stationURL after $maxAttempts attempts\n";
        next;
    }

    # Fetch station details
    my $playlist_name = (defined $customName && $customName ne '') ? $customName : ($station_obj->getTitle() || 'Unknown Playlist');
    my $station_image_url = $station_obj->getImageURL();
    my $stream_urls = $station_obj->get();

    # Write station information to the station's M3U playlist file
    open(my $station_playlist_fh, '>', "$playlistDir/$playlist_name.m3u") or die "Cannot open station playlist file: $!";

    # Write station information to the extended M3U playlist
    print $station_playlist_fh "#EXTINF:-1, $playlist_name\n";
    print $station_playlist_fh "#EXTIMG:$station_image_url\n" if ($station_image_url);

    # Check if $stream_urls is an array reference before iterating
    if (ref($stream_urls) eq 'ARRAY') {
        foreach my $stream_url (@$stream_urls) {
            print $station_playlist_fh "$stream_url\n";
        }
    } else {
        print $station_playlist_fh "$stream_urls\n";
    }

    close $station_playlist_fh;

    # Download station image if available
    if ($station_image_url) {
        my $image_data = get($station_image_url);

        if ($image_data) {
            # Determine the image extension
            my ($image_ext) = $station_image_url =~ m/\.([^.]+)$/;

            # Save station image to the playlists directory
            open(my $image_fh, '>', "$playlistDir/$playlist_name.$image_ext") or die "Unable to create image file: $!";
            binmode $image_fh;
            print $image_fh $image_data;
            close $image_fh;
        }
    }

    open my $marker_fh, '>', $markerFile or warn "Cannot create marker file $markerFile: $!\n";
    close $marker_fh if $marker_fh;

    print "Playlist created for $playlistDir/$playlist_name.m3u\n";
}
