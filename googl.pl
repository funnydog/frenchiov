#!/usr/bin/perl

use strict;
use LWP;

my $browser = LWP::UserAgent->new;
$browser->agent('toolbar');
$browser->cookie_jar({});
my $res = $browser->post('http://goo.gl/api/url',
			 [ url => 'http://www.google.com' ]);

print $res->code(), "\n";
print $res->decoded_content, "\n";

$res = $browser->post('http://goo.gl/api/history',
		      [ url => 'http://goo.gl/fKAKS']);

print $res->code(), "\n";
print $res->decoded_content, "\n";
