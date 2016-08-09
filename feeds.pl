#!/usr/bin/perl
use strict;
use warnings;
use vars qw($VERSION %IRSSI);

use Irssi;
use LWP::UserAgent qw(UserAgent);
use XML::RSSLite qw(RSSLite);
use JSON::XS qw(decode_json);
use HTML::Entities qw(decode_entities);

#use Config;
#use threads;
#my $thr = threads->create(\&sub1);
#sub sub1
#{
#    Irssi::print("PROOT");
#    sleep(10);
#}

$VERSION = '0.0.1';
%IRSSI = (
    authors => 'frenchi',
    license => 'exsinistropl',
    name => 'sticazzi-arse',
    );

my $shorten_browser = LWP::UserAgent->new;
$shorten_browser->agent('toolbar');
$shorten_browser->cookie_jar({});
sub shorten_url
{
    my ($url) = @_;
    my $res = $shorten_browser->post('http://goo.gl/api/url',
				     [ url => $url ]);
    if ($res->is_success()) {
	my $jsdata = decode_json($res->decoded_content);
	return $jsdata->{short_url};
    } else {
	return undef;
    }
}

my $feed_browser = LWP::UserAgent->new;
$feed_browser->agent('Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)');
$feed_browser->cookie_jar({});
sub get_feed
{
    my ($url) = @_;

    my ($browser, $res);
    $res = $feed_browser->get($url);
    if ($res->is_success() && $res->decoded_content) {
	my %rsshash;
	parseRSS(\%rsshash, \$res->decoded_content);
	return %rsshash;
    } else {
	return undef;
    }
}

my %lastread;
my @feeds = (
    ['ARS','http://feeds.arstechnica.com/arstechnica/index?format=xml'],
    ['PTS','http://feeds.feedburner.com/Phoronix'],
    ['LtU','http://lambda-the-ultimate.org/rss.xml'],
    );

sub rss_announce
{
    my $server = Irssi::servers();

    foreach my $feed (@feeds) {
	my ($prefix, $link) = @{$feed};
	my %rss = get_feed($link);
	if (!%rss || !defined($rss{'items'})) {
	    Irssi::print("cannot get feed for $prefix " . $link);
	    next;
	}

	my $last = $lastread{$prefix};
	if (!defined $last) {
	    $last = @{$rss{'items'}}[0]->{title};
	}

	my $state = 0;
	foreach my $item (reverse(@{$rss{'items'}})) {
	    if ($state == 0 && $last eq $item->{title}) {
		$state = 1;
	    } elsif ($state == 1) {
		my $short = shorten_url($item->{link});
		my $title = decode_entities($item->{title});
		$server->command("MSG ##fdt [$prefix] $title $short");

		$last = $item->{title};
	    } else {
	    }
	}
	$lastread{$prefix} = $last;
    }
}

rss_announce();
Irssi::timeout_add(5 * 60 * 1000, "rss_announce", "");
