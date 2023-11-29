#!/usr/bin/perl

# Fetches iHeartRadio station URLs and generates M3U playlists
# along with associated station information, including titles,
# stream URLs, and optional station images. Utilizes StreamFinder::IHeartRadio
# Perl module for data retrieval and saves data in a 'playlists' directory.
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
use StreamFinder::IHeartRadio;  # Fetch iHeartRadio station details
use LWP::Simple;               # For downloading station images
use File::Path qw(make_path);   # For managing directories

my $playlistDir = "./playlists";  # Directory to store playlists
make_path($playlistDir);

my @playlistData = (
    ["https://www.iheart.com/live/kssn-96-105/", ""],
    ["https://www.iheart.com/live/kix-104-3454/", ""],
    ["https://www.iheart.com/live/hot-1019-3442/", ""],
    ["https://www.iheart.com/live/1051-the-wolf-little-rock-93/", ""],
    ["https://www.iheart.com/live/magic-1079-3446/", ""],
    ["https://www.iheart.com/live/k-mag-991-109/", ""],
    ["https://www.iheart.com/live/933-the-eagle-3450/", ""],
    ["https://www.iheart.com/live/1003-the-edge-89/", ""],
    ["https://www.iheart.com/live/hot-949-101/", ""],
    ["https://www.iheart.com/live/b98-fort-smith-117/", ""],
    ["https://www.iheart.com/live/big-dog-959-113/", ""],
    ["https://www.iheart.com/live/news-talk-1320-kwhn-4250/", ""],

);   # Replace with your actual station URLs and empty playlist filenames

foreach my $stationInfo (@playlistData) {
    my ($stationURL, $playlistFilename) = @$stationInfo;  # Destructure array reference

    # Extract station ID from URL using regex
    my ($stationID) = $stationURL =~ m|/live/([^/]+)/|;

    my $station = StreamFinder::IHeartRadio->new($stationID, -keep => ['secure_shoutcast', 'secure', 'any'], -skip => 'rtmp');

    unless ($station) {
        warn "Invalid URL or no streams found for $playlistFilename\n";
        next;
    }

    my $stationTitle = $station->getTitle();  # Fetch station title/name

    # Remove unwanted characters from the station name to use as playlist and image filenames
    my $safeFilename = $stationTitle =~ s/[^\w.-]+/_/gr;

    $playlistFilename = "$playlistDir/$safeFilename.m3u";  # Set playlist filename using station name within the directory
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
}

