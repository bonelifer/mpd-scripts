#!/usr/bin/perl

# Fetches TuneIn radio station URLs and generates M3U playlists
# with associated station information including titles, stream URLs,
# and optional station images. Utilizes StreamFinder::Tunein Perl
# module for data retrieval and saves data in an 'archive' directory.
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
use StreamFinder::Tunein;  # Fetch TuneIn station details
use LWP::Simple;          # For downloading station images

# Array of station URLs and their corresponding playlist names
my @stations = (
    { url => 'https://tunein.com/radio/KUAR-891-s35843/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KUAF-913-s35839/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KUAF-2-913-s97277/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KUAF-3-913-s97278/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KUHS-LP-Hot-Springs-1025-s252058/', playlist_name => '' },
    { url => 'https://tunein.com/radio/Power-92-Jams-923-s33199/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KVRE-929-s26151/', playlist_name => '' },
    { url => 'https://tunein.com/radio/The-Point-941-s33572/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KSSN-96-957-s35494/', playlist_name => '' },
    { url => 'https://tunein.com/radio/US-97-975-s34897/', playlist_name => '' },
    { url => 'https://tunein.com/radio/B985-s35941/', playlist_name => '' },
    { url => 'https://tunein.com/radio/1003-The-Edge-s34781/', playlist_name => '' },
    { url => 'https://tunein.com/radio/Rock-1015-s33220/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KJDS-1019-s26744/', playlist_name => '' },
    { url => 'https://tunein.com/radio/1029-KARN-News-Radio-s36053/', playlist_name => '' },
    { url => 'https://tunein.com/radio/1037-The-Buzz-s31328/', playlist_name => '' },
    { url => 'https://tunein.com/radio/1051-The-Wolf-Little-Rock-s34059/', playlist_name => '' },
    { url => 'https://tunein.com/radio/KLAZ-1059-s33665/', playlist_name => '' },
    { url => 'https://tunein.com/radio/Alice-1077-s33655/', playlist_name => '' },
    { url => 'https://tunein.com/radio/CER2-Radio-690-s32531/', playlist_name => '' },
    # Add more stations as needed
);

# Create archive directory if it doesn't exist
my $archive_dir = 'archive';
unless (-e $archive_dir && -d $archive_dir) {
    mkdir $archive_dir or die "Unable to create directory: $!";
}

# Iterate through each station and fetch station images and generate M3U playlists
foreach my $station (@stations) {
    my $station_obj = StreamFinder::Tunein->new($station->{url});

    next unless ($station_obj);  # Skip invalid URLs or stations without streams

    # Fetch station details
    my $playlist_name = $station->{playlist_name} || $station_obj->getTitle() || 'Unknown Playlist';
    my $station_image_url = $station_obj->getImageURL();
    my $stream_urls = $station_obj->get();

    # Write station information to the station's M3U playlist file
    open(my $station_playlist_fh, '>', "$archive_dir/$playlist_name.m3u") or die "Cannot open station playlist file: $!";

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

            # Save station image to the archive directory
            open(my $image_fh, '>', "$archive_dir/$playlist_name.$image_ext") or die "Unable to create image file: $!";
            binmode $image_fh;
            print $image_fh $image_data;
            close $image_fh;
        }
    }
}

