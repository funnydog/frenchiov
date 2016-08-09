#!/usr/bin/perl
use strict;
use warnings;
use vars qw($VERSION %IRSSI);

use Irssi;
$VERSION = '0.0.1';
%IRSSI = (
    authors => 'frenchi',
    license => 'avvepl',
    name => 'avveadve',
    );

my %players;

# quante belle locazioni

my %mymap = (
    'Inizio del sentiero' => [
	'Sei all\'inizio di un sentiero ghiaioso. Ai lati si innalzano maestosi dei possenti faggi le cui fronde si perdono nel buio del bosco.',
	['est', 'passaggio', 'Il bivio']
    ],

    'Il bivio' => [
	'Ti trovi a un bivio: il sentiero qui si dirama in due direzioni. A est scorgi in lontananza una rupe, mentre a sud la pendenza si fa più ripida. L\'aria è caldissima.',
	['ovest', 'passaggio', 'Inizio del sentiero'],
	['est', 'passaggio', 'Muro di roccia'],
	['sud', 'passaggio', 'Sentiero in salita']
    ],

    'Muro di roccia' => [
	'La strada si ferma di fronte a un maestoso muro di roccia, finemente cesellato da abili artisti. Ti sembra di intravvedere una fine iscrizione.',
	['ovest', 'passaggio', 'Il bivio']
    ],

    'Sentiero in salita' => [
	'Stai sudando copiosamente a causa del sentiero impegnativo. In basso ormai vedi le chiome del bosco. Il clima è mite e gradevole e la leggera brezza riesce a rinfrescarti un po\'.',
	['nord', 'passaggio', 'Il bivio'],
	['ovest', 'passaggio', 'Sentiero irto'],
    ],

    'Sentiero irto' => [
	'Il sentiero è diventato così stretto che temi di cadere di sotto. Camminando franano dei massi che ineluttabilmente rotolano a valle.',
	['est', 'passaggio', 'Sentiero in salita'],
	['sud', 'passaggio', 'Sentiero panoramico']
    ],

    'Sentiero panoramico' => [
	'Il sentiero ora è un piccolo lembo spianato a caduta libera su un precipizio di cui non scorgi il fondo. Un vento impetuoso minaccia di farti cadere nel vuoto.',
	['nord', 'passaggio', 'Sentiero irto'],
	['est', 'passaggio', 'Passo del fdt']
    ],

    'Passo del fdt' => [
	'Sei al passo del FDT. Per terra scorgi i tristi resti di epiche battaglie. Ti rendi conto che il luogo ha oramai perduto gli antichi splendori di un tempo.',
	['ovest', 'passaggio', 'Sentiero panoramico'],
	['nord', 'passaggio', 'Sulla cima'],
	['est', 'passaggio', 'Altopiano di luino'],
    ],

    'Sulla cima' => [
	'Sei sulla cima del monte. Che fare? Qualcuno ha inciso rozzamente un glifo su un masso.',
	['sud', 'passaggio', 'Passo del fdt'],
    ],

    'Altopiano di luino' => [
	'Un cartello segnala che sei arrivato all\'altopiano di luino. Dall\'alto il gracchiare dei corvi sottolinea che sei giunto alla meta.',
	['ovest', 'passaggio', 'Passo del fdt'],
    ],

    );

my @objects = (
    ['un petofono', 'E\' un petofono che sonnecchia ai tuoi piedi', 1],

    ['un\'iscrizione', 'E\' un\'iscrizione che descrive le gesta del pavido avvegul. Le sue imprese sono raccontate nei minimi dettagli. Una stranissima scritta attira la tua attenzione', 0],

    ['una stranissima scritta', 'Dice: "E\' DIETRO DI TE". Ti giri di scatto ma dietro di te non c\'è essuno. La frase ti lascia comunque sgomento senza alcun motivo apparente.', 0],

    ['un cartello', 'Dice: "Altopiano di Luino - Mettersi in posizione consona e attendere"', 0],

    ['un glifo', 'E\' una rana ballerina. Nella tua mente risuona "Ma tu hai mai aperto access? Penso proprio di no perché sennò cercheresti di dare aria al cervello e non alla buca del culo.... prima di rispondere alla cazzo di cane"', 0],

    );

my %objects_locations = (

    'un petofono' => 'Inizio del sentiero',
    'un\'iscrizione' => 'Muro di roccia',
    'una stranissima scritta' => 'Muro di roccia',
    'un cartello' => 'Altopiano di luino',
    'un glifo' => 'Sulla cima',

    );

sub get_player
{
    my ($nick) = @_;

    if (exists($players{$nick})) {
	return $players{$nick};
    } else {
	$players{$nick} = {
	    'name' => $nick,
	    'objects' => [],
	    'map' => \%mymap,
	    'location' => 'Inizio del sentiero'
	};
	return $players{$nick};
    }
}

sub describe_location
{
    my ($location, $curmap) = @_;
    return $curmap->{$location}[0];
}

sub describe_path
{
    my ($dir, $type, $next) = @{$_[0]};
    return "Un $type va a $dir.";
}

sub describe_paths
{
    my ($location, $curmap) = @_;
    my $path = $curmap->{$location};

    my $str = "";
    for my $i ( 1 .. $#{$path} ) {
	$str = $str . " " . describe_path($path->[$i]);
    }
    return $str;
}

sub is_at
{
    my ($obj, $loc, $objloc) = @_;
    if ($objloc->{$obj} eq $loc) {
	return 1;
    } else {
	return 0;
    }
}

sub describe_floor
{
    my ($loc, $objs, $objloc) = @_;
    my $str = "";
    foreach my $obj (@{$objs}) {
	if ($obj->[2] && is_at($obj->[0], $loc, $objloc)) {
	    $str = $str . " Vedi $obj->[0] per terra.";
	}
    }
    return $str;
}

sub describe_players
{
    my ($player) = @_;

    my ($str, $count) = ("", 0);
    while (my ($key, $value) = each %players) {
	if ($value->{location} eq $player->{location} &&
	    $value->{name} ne $player->{name})
	{
	    $count += 1;
	    $str = $str . " " . $value->{name};
	}
    }
    if ($count > 1) {
	return " Qui ci sono" . $str . ".";
    } elsif ($count == 1) {
	return " Qui c'è". $str . ".";
    } else {
	return $str;
    }
}

sub look
{
    my ($player, $message) = @_;

    return
	describe_location($player->{location}, $player->{map}) .
	describe_paths($player->{location}, $player->{map}) .
	describe_floor($player->{location}, \@objects, \%objects_locations) .
	describe_players($player);
}

sub look_at
{
    my ($player, $message) = @_;

    foreach my $obj (@objects) {
	if (is_at($obj->[0], $player->{location}, \%objects_locations)) {
	    if ($obj->[0] =~ /$message/) {
		return $obj->[1];
	    }
	}
    }

    while (my ($key, $value) = each %players) {
	if ($key ne $player->{name} &&
	    $value->{location} eq $player->{location} &&
	    $key =~ /$message/) {
	    return "Stai fissando $key, poi volgi lo sguardo altrove per non attirare troppo la sua attenzione.";
	}
    }

    return "Per quanto ti sforzi non riesci a vedere $message.";
}

sub walk_towards
{
    my ($player, $direction) = @_;

    my $paths = $player->{map}->{$player->{location}};
    for my $i ( 1 .. $#{$paths} )
    {
	if ($paths->[$i][0] eq $direction) {
	    $player->{location} = $paths->[$i][2];
	    return look($player);
	}
    }
    return "Non puoi andare in quella direzione";
}

sub just_arrived
{
    my ($player, $message) = @_;

    return "E' appena arrivato $player->{name}.";
}

sub just_gone
{
    my ($player, $message) = @_;
    return "$player->{name} se n'è appena andato.";
}

sub talk
{
    my ($player, $message) = @_;

    return $player->{name} . ' dice: "' . $message. '"';
}

sub help
{
    my ($player, $message) = @_;

    return "Prova ad utilizzare questi verbi: osserva, osserva <cosa>, vai a <direzione>, '<frase> per parlare con qualcuno; esci per uscire da questo interessantissssssimo gioco (ghost)";
}

sub remove_player
{
    my ($player, $message) = @_;

    delete $players{$player->{name}};

    return "$player->{name} spirò.";
}

sub tell_player
{
    my ($player, $server, $message) = @_;

    $server->send_message($player->{name}, $message, 1);
}

sub tell_others
{
    my ($player, $server, $message, $location) = @_;

    if (!defined($location)) {
	$location = $player->{location};
    }

    while (my ($key, $value) = each %players)
    {
	if ($key ne $player->{name} &&
	    $location eq $value->{location})
	{
	    tell_player($value, $server, $message);
	}
    }
}

sub tell_any
{
    my ($player, $server, $message) = @_;

    while (my ($key, $value) = each %players)
    {
	tell_player($value, $server, $message);
    }
}

sub demux
{
    my ($server, $msg, $nick, $address) = @_;

    my $player = get_player($nick);
    if ($msg =~ /^aiuto$/) {
	tell_player($player, $server,
		    help($player, ""));
    } elsif ($msg =~ /vai (verso|a) (\w+)/) {

	my $prevloc = $player->{location};
	tell_player($player, $server,
		    walk_towards($player, $2));

	if ($prevloc ne $player->{location})
	{
	    tell_others($player, $server,
			just_gone($player, ""),
			$prevloc);
	    tell_others($player, $server,
			just_arrived($player, ""));
	}

    } elsif ($msg =~ /osserva (\w+)/) {
	tell_player($player, $server,
		    look_at($player, $1));
    } elsif ($msg =~ /osserva/) {
	tell_player($player, $server,
		    look($player, ""));
    } elsif ($msg =~ /^'(.*)/) {
	tell_others($player, $server,
		    talk($player, $1));
    } elsif ($msg =~ /esci/) {
	tell_others($player, $server,
		    remove_player($player, ""));
	tell_player($player, $server,
		    "Sei uscito dal gioco.");
    }
}

Irssi::signal_add('message private', 'demux');
