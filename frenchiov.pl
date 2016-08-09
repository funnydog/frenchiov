use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
$VERSION = '1.00';
%IRSSI = (
    authors => 'frenchi',
    contact => 'frenchi',
    name => 'Test',
    description => 'Test',
    license => 'Public Domain',
    );

my %timeouts;
my %ratelimit;

sub rl_remove
{
    my $data = shift;
    if (defined($data->{host})) {
	delete $ratelimit{$data->{class}}{$data->{host}};
    } else {
	delete $ratelimit{$data->{class}};
    }
}

sub rl_set_timeout
{
    my ($class, $timeout) = @_;

    $timeouts{$class} = $timeout;
}

sub rl_get_timeout
{
    my $class = shift;

    if (exists $timeouts{$class}) {
	return $timeouts{$class};
    } else {
	return 15 * 60;
    }
}

sub pass_ratelimit
{
    my ($class, $server, $channel, $nick) = @_;

    # rate limiting avoid the abuse
    my $chanrec = $server->channel_find($channel);
    return 0 if !$chanrec;

    my $nickrec = $chanrec->nick_find($nick);
    return 0 if !$nickrec;

    return 0 if (exists $ratelimit{$class}{$nickrec->{host}});

    $ratelimit{$class}{$nickrec->{host}} = Irssi::timeout_add_once(
	1000 * rl_get_timeout($class),
	'rl_remove', { class => $class, host => $nickrec->{host} });

    return 1;
}

sub send_ratelimit
{
    my ($class, $server, $channel, $nick, $msg) = @_;

   if (pass_ratelimit($class, $server, $channel, $nick)) {
	$server->command("MSG $channel $msg");
    }
}

sub rl_pass
{
    my $class = shift;

    return 0 if (exists $ratelimit{$class});

    $ratelimit{$class} = Irssi::timeout_add_once(
	1000 * rl_get_timeout($class), 'rl_remove', { class => $class });

    return 1;
}

sub rl_command
{
    my ($class, $server, $command) = @_;

    if ($command && rl_pass($class)) {
	$server->command($command);
    }
}


# fdt hooks (ghost)
use Fdt;
use LWP;
use URI;
use HTML::TreeBuilder;
use Encode;

use HTML::Entities qw( decode_entities );
use constant FB_SPACE => sub { ' ' };

my $browser = LWP::UserAgent->new;
$browser->proxy(http => 'socks://localhost:9050');
$browser->agent('Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)');
$browser->cookie_jar({'PITROOL_DISCLAIMER'=>1});

# get the cookie
#$browser->get('http://www.forumdeitroll.it/');

sub fetch_url
{
    my $url = shift;
    my $res = $browser->get($url);

    return '' unless $res->is_success;

    return $res->decoded_content;
}

sub fetch_tree
{
    my $url = shift;

    my $data = fetch_url($url);
    if ($data) {
	my $tree = HTML::TreeBuilder->new;
	return $tree->parse($data);
    } else {
	return undef;
    }
}

sub fdt_extract_data
{
    my $url = shift;

    # get the HTML tree
    my $tree = fetch_tree($url);

    # code
    my @el = $tree->look_down('_tag' => 'a', 'title' => 'Ascolta il codice');
    my $captcha_url = URI->new_abs($el[0]->attr('href'), $url);
    my $data = fetch_url($captcha_url);
    my $code = Fdt::captcha($data, length $data);

    # viewstate
    @el = $tree->look_down('_tag' => 'input', 'name' => '__VIEWSTATE');
    my $viewstate = $el[0]->attr('value');

    # event validation
#    @el = $tree->look_down('_tag' => 'input', 'name' => '__EVENTVALIDATION');
#    my $evalid = $el[0]->attr('value');

    # title
    @el = $tree->look_down('_tag' => 'input', 'name' => 'txtTitle');
    my $title = (scalar(@el)>0)?$el[0]->attr('value'):'';

    # body
    @el = $tree->look_down('_tag' => 'textarea', 'name' => 'txtPost');
    my $body = '';
    if (scalar(@el)) {
	$body = join('', $el[0]->content_list());
#	$body = decode_entities($body);
	$body = substr $body, 4;
    }

    return {
	title     => $title,
	body      => $body,
	code      => $code,
	viewstate => $viewstate,
#	evalid    => $evalid,
    };
}

sub fdt_post_message
{
    my ($title, $text) = @_;

    my $url      = 'http://www.forumdeitroll.it/p.aspx?f_id=127';
    my $data     = fdt_extract_data($url);
    my $response = $browser->post(
	$url, [
	    txtTTitolo        => $title,
	    txtTBody          => $text,
	    cmdPostMessage    => 'Invia',
	    __VIEWSTATE       => $data->{viewstate},
#	    __EVENTVALIDATION => $data->{evalid},
	    txtCodeNumber     => $data->{code},
	]);

    return $response->code() == 302 ? 1 : 0;
}

sub fdt_reply_message
{
    my ($msgid, $title, $text, $quote) = @_;

    my $url      = "http://www.forumdeitroll.it/r.aspx?m_id=$msgid&quote=1&m_rid=0";
    my $data     = fdt_extract_data($url);

    if (!$title) {
	$title = $data->{title};
    }

    if ($quote) {
	$text = Encode::encode("iso-8859-1", $data->{body}) . "\r\n" . $text;
    }

    my $response = $browser->post(
	$url, [
	    txtTitle          => $title,
	    txtPost           => $text,
	    cmdPostMessage    => 'Invia',
	    __VIEWSTATE       => $data->{viewstate},
	    __EVENTVALIDATION => $data->{evalid},
	    txtCodeNumber     => $data->{code},
	]);

    return $response->code() == 302 ? 1 : 0;
}

# other unuseful things
sub cycle_nicks
{
    my $par = shift;
    my $server = $par->{server};
    my @nicklist = split(' ', $par->{nicklist});
    my $index = $par->{index};

    if ($index eq scalar(@nicklist)) {
	$server->command('NICK ' . $server->{nick});
    } else {
	$server->command('NICK ' . @nicklist[$index]);
	$par->{index} = $index + 1;
	Irssi::timeout_add_once(2 * 1000, 'cycle_nicks', $par);
    }
}

sub fortune
{
    my @ret;
    open ( FH, "/usr/bin/fortune|") or die $!;
    foreach my $row(<FH>) {
	$row =~ s/[\t]/ /g;
	push(@ret, $row);
    }
    close FH;

    return @ret;
}

my @greets = (
    {
        nick => 'suoranciata',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "sempre sialodato");
	}
    },
    {
	host => 'suoranciata',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "Deicide - Homage for $nick");
	}
    },
    {
	nick => 'sarrusofono',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "(format t \"~{~a~^ ~}?~%\" '(ma trombare))");
	},
    },
    {
	nick => '/[Nn]at[h]?a[n]?',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "ME NE FREGO!™");
	}
    },
    {
	nick => '[jJ]olanda',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "Ma trombare?!");
	}
    },
    {
	nick => 'dada',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    if (pass_ratelimit("greets", $server, $chan, $nick)) {
		foreach my $row (fortune()) {
		    $server->command("MSG $chan $row");
		}
	    }
	}
    },
    {
	nick => 'tenka',
	greet => sub {
	    my ($server, $chan, $nick) = @_;
	    send_ratelimit("greets", $server, $chan, $nick, "hòla manìaco!");
	}
    },
    );

sub load_array
{
    open(FILE, $_[0]) or die ("Unable to open the file $_[0]");
    my @data = <FILE>;
    close(FILE);
    return @data;
}

my @mostri;

sub mostri_reload
{
    @mostri = load_array('/home/utonto/frasario.txt');
}


sub greetings
{
    my ($cr, $nick_list) = @_;

    return if ($cr->{name} ne "##fdt");

    foreach my $nr (@{$nick_list}) {
	foreach my $greet (@greets) {
	    if (exists $greet->{nick} && $nr->{nick} =~ $greet->{nick}) {
		$greet->{greet}($cr->{server}, $cr->{name}, $nr->{nick});
		goto SKIP;
	    } elsif (exists $greet->{host} && $nr->{host} =~ $greet->{host}) {
		$greet->{greet}($cr->{server}, $cr->{name}, $nr->{nick});
		goto SKIP;
	    }
	}
	if (int(rand(10)) eq 1) {
	    send_ratelimit("greets", $cr->{server}, $cr->{name}, $nr->{nick},
			   "zitti zitti che adesso c'è $nr->{nick} :|");
	} else {
#	    my $who = $mostri[int(rand(scalar(@mostri)-1))];
#	    send_ratelimit("greets", $cr->{server}, $cr->{name}, $nr->{nick},
#			   "$nr->{nick}: che $who sia con te!");
	}

      SKIP:
    }
}

sub desax_reop
{
    my $target = shift;

    $target->{chan}->command("op " . $target->{nick});
}

sub deop_sax
{
    my ($channel) = @_;

    my $nick = $channel->nick_find_mask("*!*@*sarrusofo*");
    if ($nick) {
	    $channel->command("deop " . $nick->{nick});
	    my $target = {nick => $nick->{nick}, chan=> $channel};
	    Irssi::timeout_add_once(5 * 1000, "desax_reop", $target);
    }
}

sub kick_sax
{
    my ($channel) = @_;

    my $nick = $channel->nick_find_mask("*!*@*sarrusofo*");
    if ($nick) {
	    $channel->command("kick " . $nick->{nick});
    }
}

sub desax
{
    my ($msg, $server, $channel) = @_;

    if ($channel->{type} ne 'CHANNEL') {
	# nothing
    } elsif ($msg eq '/topic -delete') {
	#kick_sax($channel);
    } else {
	# desax banwords
	if ( $msg =~ /goo\.gl/) {
	     #deop_sax($channel);
	}
    }
}

my @faq = (
    {
	question => '\b(?i:pacciani)\b',
	answer => sub {
	    my ($server, $msg, $nick, $address, $target) = @_;
	    rl_command("faq", $server, "MSG $target $nick: quel violento omicida, stupratore delle figlie, alcolizzato, ignorante?");
	}
    },
    {
	question => '\b(?i:giambo)\b',
	answer => sub {
	    my ($server, $msg, $nick, $address, $target) = @_;

	    my $channel = $server->channel_find($target);
	    if (defined($channel) && ! $channel->nick_find("Giambo")) {
		rl_command("faq", $_[0], "MSG $target (;°)");
	    }
	}
    },
    {
	question => '\bAC([K]+)\b',
	answer => sub {
	    if (int(rand(10)) eq 1) {
		rl_command("faq", $_[0], "MSG $_[4] SYN-AC" . "K"x length($1));
	    } else {
		rl_command("faq", $_[0], "MSG $_[4] RS" . "T"x length($1));
	    }
	}
    },
    {
	question => '\bSY([N]+)\b',
	answer => sub {
	    rl_command("faq", $_[0], "MSG $_[4] AC" . "K"x length($1));
	}
    },
#    {
#	question => 'frenchiov:\s*bot\s*(.*)',
#	answer => sub {
#	    my ($server, $msg, $nick, $address, $target) = @_;
#	    if (rl_pass("bot")) {
#		$server->command("MSG $target $nick: " . create_sentence($1));
#	    }
#	}
#    },
#    {
#	question => 'frenchiov:\s*http:\/\/www\.forumdeitroll\.it\/m\.aspx\?m_id=(\d+)[^\s]*\s*(.*)',
#	answer => sub {
#	    my ($server, $msg, $nick, $address, $target) = @_;
#	    if (($1) && rl_pass("bot")) {
#		frenchiov_reply($1, $server, $target, $nick, $2);
#	    } else {
#		$server->command("MSG $target $nick: non ci sono riuscito :(");
#	    }
#	}
#    },
#    {
#	question => 'frenchiov:\s*topic\s*(.*)',
#	answer => sub {
#	    my ($server, $msg, $nick, $address, $target) = @_;
#	    if (rl_pass("bot")) {
#		$server->command(
#		    "TOPIC $target " . create_sentence($1));
#	    }
#	}
#    },
    {
	question => 'frenchi:\s*cookie\b',
	answer => sub {
	    my ($server, $msg, $nick, $address, $target) = @_;
	    if (rl_pass("cookie")) {
		foreach my $row (fortune()) {
		    $server->command("MSG $target $row");
		}
	    }
	}
    },
    {
	question => '[><]([+-])[><]',
	answer => sub {
	    my ($server, $msg, $nick, $addr, $target) = @_;
	    my $plength = Irssi::settings_get_int("frenchiov_penis");
	    if ($1 eq '+') {
		if ($plength >= 70) {
		    $server->command("MSG $target 8=PUFFF!!!=D");
		    $plength = 1;
		} else {
		    $plength++;
		    $server->command("MSG $target 8" . "="x $plength . "D");
		}
	    } elsif ($1 eq '-') {
		if ($plength == 1) {
		    $server->command("MSG $target minimì not allowed :@");
		} else {
		    $plength--;
		    $server->command("MSG $target 8" . "="x $plength . "D");
		}
	    } else {
		$server->command("MSG $target (|)");
	    }
	    Irssi::settings_set_int("frenchiov_penis", $plength);
	}
    },
    {
	question => '^\s*hi\s*$',
	answer => sub {
	    my ($server, $msg, $nick, $addr, $target) = @_;
	    rl_command("faq", $server, "MSG $target lo");
	}
    },
    {
	question => '^\s*lo\s*$',
	answer => sub {
	    my ($server, $msg, $nick, $addr, $target) = @_;
	    rl_command("faq", $server, "MSG $target hi");
	}
    },
    {
	question => '^\s*hey\s*$',
	answer => sub {
	    my ($server, $msg, $nick, $addr, $target) = @_;
	    rl_command("faq", $server, "MSG $target ho");
	}
    },
    );

sub autoanswer
{
    my ($server, $msg, $nick, $address, $target) = @_;

    return if $target ne "##fdt";

    foreach my $el(@faq) {
	if ($msg =~ m/$el->{question}/) {
	    $el->{answer}->(@_);
	    return;
	}
    }
}

sub frenchiov_reply
{
    my ($msgid, $server, $channel, $nick, $params) = @_;

    my $body = create_sentence($params) .
	"\r\n\r\n (ghost) (cylon) (ghost)";
    $body = Encode::encode("iso-8859-1",
			   Encode::decode("utf8", $body, FB_SPACE ));
    my $resp = fdt_reply_message($msgid, '', $body, 1);
    $server->command("MSG $channel $nick: non ci sono riuscito :(")
	unless $resp;
}

sub frenchiov_cmd
{
    my ($par, $server, $witem) = @_;

    if ($par =~ /http:\/\/www\.forumdeitroll\.it\/m\.aspx\?m_id=(\d+)[^\s]*\s?(.*)/) {
	frenchiov_reply($1, $server, $witem->{name}, $server->{nick}, $2);
    } else {
	Irssi::print("no match");
    }
}

my $MAXGEN = 10000;
my $NONWORD = "\n";
my %statetab;

sub build_from_row
{
    my $row = shift;

    return if $row =~ /^---/;
    return if $row =~ /-!-/;

    $row =~ s/^\d{2}:\d{2} //;
    $row =~ s/^<.*> //;
    $row =~ s/(?:^\w+:)+ //;
    $row =~ s/[\t\s]+$//;
    $row =~ s/^[\t\s]+//;
    $row =~ s/(?:http[s]*:\/\/[^\s]*[\s\t]*)+//;
    $row =~ s/[*] //;
    return if $row =~ /^http[s]*:\/\//;
    return if $row =~ /^!addquote/;
    return if $row =~ /^\[.*\]/;

    my @arr = split(/ /, $row);

    # learn only from sentences with equal or more than 4 words
    return if (scalar(@arr)<4);

    my ($w1, $w2) = ($NONWORD, $NONWORD);
    foreach (@arr) {
	push(@{$statetab{$w1}{$w2}}, $_);
	($w1, $w2) = ($w2, $_);
    }
    push(@{$statetab{$w1}{$w2}}, $NONWORD);
}

sub build_from_file
{
    open(FH, shift) or die $!;
    while (<FH>) {
	build_from_row($_);
    }
    close FH;
}

sub create_sentence
{
    my ($w1, $w2) = ($NONWORD, $NONWORD);
    my ($i, @res);

    my ($p1, $p2) = split(' ', @_[0]);

    if ($p2) {
	$w1 = $p1;
	$w2 = $p2;
    } elsif ($p1) {
	$w2 = $p1;
    }

    while (scalar(@res) == 0) {
	for ($i = 0; $i < $MAXGEN; $i++) {
	    my $suf = $statetab{$w1}{$w2};
	    last if ((my $t = $suf->[rand @$suf]) eq $NONWORD);

	    push(@res, $t);
	    ($w1, $w2) = ($w2, $t);
	}
    }
    if ((substr $res[-1],-1,1) ne "\n") {
	push(@res, "\r\n");
    }

    if ($p2) {
	return $p1 . " " . $p2 . " " . join(" ", @res);
    } elsif ($p1) {
	return $p1 . " " . join(" ", @res);
    } else {
	return join(" ", @res);
    }
}

sub autolearn
{
    my ($server, $msg, $nick, $address, $target) = @_;
    build_from_row($msg);
}

sub generate
{
    my ($params, $server, $witem) = @_;

    if ($witem) {
	$server->command("MSG " . $witem->{name} . " " .
			 create_sentence($params));
    }
}

my $timer;

sub autogenerate
{
    my $target = shift;
    generate($target->{params}, $target->{server}, $target->{witem});
}

sub startmarkov
{
    my ($params, $server, $witem) = @_;

    return if $timer;

    $timer = Irssi::timeout_add(
	1000 * 60 * 30, "autogenerate",
	{ params => $params, server => $server, witem => $witem });
}

sub stopmarkov
{
    if ($timer) {
	Irssi::timeout_remove($timer);
	undef $timer;
    }
}

sub markovtrain
{
    my ($params, $server, $witem) = @_;
    if ($params) {
	build_from_file($params);
    }
}

sub animation
{
    my ($par, $server, $witem) = @_;

    my $topic = $witem->{topic};
    open(FH, "/home/utonto/animation.txt") or die $!;
    while (<FH>) {
	$server->command("TOPIC " . $witem->{name} . " " . $_);
    }
    close FH;
    $server->command("TOPIC " . $witem->{name} . " " . $topic);
}

Irssi::settings_add_int("misc", "frenchiov_penis", 1);
rl_set_timeout("bot", 60);
rl_set_timeout("cookie", 60);
rl_set_timeout("greetings", 30);
rl_set_timeout("greets", 30);
rl_set_timeout("faq", 30);
#build_from_file("/home/utonto/irclogs/Freenode/##fdt.log");
mostri_reload();


#Irssi::signal_add('gui exit', 'save_settings');
Irssi::signal_add_last('massjoin', 'greetings');
Irssi::signal_add_first('send message', 'desax');
Irssi::signal_add_first('send command', 'desax');
Irssi::signal_add_last('message public', 'autoanswer');
Irssi::signal_add_last('message public', 'autolearn');
#Irssi::command_bind('markov', 'generate');
#Irssi::command_bind('startmarkov', 'startmarkov');
#Irssi::command_bind('stopmarkov', 'stopmarkov');
#Irssi::command_bind('markovtrain', 'markovtrain');
#Irssi::command_bind('frenchiov', 'frenchiov_cmd');
Irssi::command_bind('mostri', 'mostri_reload');
Irssi::command_bind('animation', 'animation');
#Irssi::command_bind('hello', 'cmd_test');
