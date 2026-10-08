package CHacker;

use 5.022;
use warnings;


use Exporter qw(import);
our @EXPORT = qw(process_command_line e sine);

use Getopt::Long qw(GetOptions);

use Time::HiRes qw(gettimeofday tv_interval);
use Math::Trig qw(asin acos);

use MIDI::RtMidi::FFI::Device::In;
use MIDI::RtMidi::FFI::Device;
use MIDI::Stream::Decoder;

use AnyEvent;
use AnyEvent::Run;



sub new {
	my $class = shift;
	my $self = {};
	return bless $self, $class;
}

# Usefull util for parsing command-line
sub process_command_line {
	my $usage = pop; # Get last param, it's Usage text
	my @opts  = @_;  # Get params
	
	# Prepare from GetOptions syntax option to key-names
	my $prepare = sub {
		my $opt = shift;
		$opt =~ s/\=s$//;
		$opt =~ s/^\w\|(\w+)$/$1/;
		return $opt;
	};
	
	my %args = ();
	GetOptions(map {$_ => \$args{$prepare->($_)}} @opts);
	
	# Show usage, it catchet --help command-line param
	say $usage and exit() if $args{help};
	
	return %args;
}

sub pi {
	return 3.14159265358979323846;
}

sub config {
	state $config = {
		DEFAULT_SAMPLE_RATE 	=> 44100,
		DEFAULT_VOLUME      	=> 1,
		NOTES_FREQUES 			=> [qw/13.75000 14.56762 15.43385 16.35160 17.32391 18.35405 19.44544 20.60172 21.82676 23.12465 24.49971 25.95654 27.50000 29.13524 30.86771 32.70320 34.64783 36.70810 38.89087 41.20344 43.65353 46.24930 48.99943 51.91309 55.00000 58.27047 61.73541 65.40639 69.29566 73.41619 77.78175 82.40689 87.30706 92.49861 97.99886 103.8262 110.0000 116.5409 123.4708 130.8128 138.5913 146.8324 155.5635 164.8138 174.6141 184.9972 195.9977 207.6523 220.0000 233.0819 246.9417 261.6256 277.1826 293.6648 311.1270 329.6276 349.2282 369.9944 391.9954 415.3047 440.0000 466.1638 493.8833 523.2511 554.3653 587.3295 622.2540 659.2551 698.4565 739.9888 783.9909 830.6094 880.0000 932.3275 987.7666 1046.502 1108.731 1174.659 1244.508 1318.510 1396.913 1479.978 1567.982 1661.219 1760.000 1864.655 1975.533 2093.005 2217.461 2349.318 2489.016 2637.020 2793.826 2959.955 3135.963 3322.438 3520.000 3729.310 3951.066 4186.009 4434.922 4698.636 4978.032 5274.041 5587.652 5919.911 6271.927 6644.875 7040.000 7458.620 7902.133 8372.018/],
		NOTES					=> ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'H'],
	};
	
	return $config;
}

sub note_rate {
	my $class = shift;
	my $note  = shift;
	return $class->config->{NOTES_FREQUES}->[$note + 51];
}

sub sine {
	my $note = shift;
	#my $note2 = shift;
	
	my $len = shift;
	my $mod = CHacker->note_rate($note) / 44100;
	#my $mod2 = CHacker->note_rate($note2) / 44100;
	
	my @s1 = map { sin(pi() * $_ * $mod ) } 0 .. (44100 * $len - 1);
	#my @s2 = map { sin(pi() * $_ * $mod2 ) } 0 .. (44100 * $len - 1);
	
	my @buff;
	for (0..scalar (@s1) - 1) {
		push @buff, ($s1[$_]);#+0*$s2[$_])/2;
	}
	
	return @buff;
	
	#my $buff = pack "f*", @buff;
	
	#for (@buff) {
	#	my $s = int ($_ * 32767 + 0.5);
	#	print pack('s', $s);
	#}
	#return $buff;
}

sub e {
	my $a = shift;
	my $b = shift;
	my $c = sqrt($a*$a + $b*$b);
	
	my $n = shift;
	my $hook = shift;
	
	my @s;
	
	my $modulation = CHacker->note_rate(0) / 44100;

	my $offset = $n * $modulation;

	my $x;
	
	my $alpha;
	if ($a > $b) {
		$x = $b / $a;
		$alpha = asin($b / $c);

		$c = acos($alpha / 2.0) * $b;
		$a = sqrt($c*$c - $b*$b);
	} else {
		$x = $b / $a;
		$alpha = asin($a / $c);

		$c = acos($alpha / 2.0) * $a;
		$b = sqrt($c*$c - $a*$a);
	}
	
	if ($c < 10) {
		$a *= 10;
		$b *= 10;
	}
	
	$c = sqrt($a*$a+$b*$b);
		
	return $hook->(
		$alpha,
		$offset
	);
}


sub init_midi {
	my $self = shift;


	# 1. Initialize and open the input port
	my $midi_in = MIDI::RtMidi::FFI::Device::In->new();


	my @midi_devices = sort keys %{$midi_in->get_all_port_names};
	
	say "Select MIDI-Device:";
	say "-"x80;
	for (1..scalar @midi_devices) {
		say "$_. " . $midi_devices[$_-1];
	}
	say "-"x80;

	print "Select device > ";
	my $dev = <STDIN>;
	chomp $dev;

	$dev = $midi_devices[$dev - 1] // die "Wrong devices";

	$midi_in->open_port_by_name($dev);
	
	$self->{midi_in} = $midi_in;
}

sub map_midi {
	my $self = shift;
		
	say "Midi-map for controller: touch pitcher and next press [Enter]!";

	my $SIZE = 42;

	my $bus = '';

	my $midi_in = $self->{midi_in};
	
	my $fh = $midi_in->get_fh;
	my $decoder = MIDI::Stream::Decoder->new;
	$decoder->attach_callback( all => sub {
		my ($event) = @_;
		print "Received event: ";
		my @a = $event->as_arrayref->@*;
		say join ', ', @a;
		$bus = $a[0];
	});


	my $cv = AnyEvent->condvar;

	my $io = AnyEvent->io(
	   fh 	=> \*STDIN,
	   poll => 'r',
	   cb 	=> sub {
		  my $input = <STDIN>;
		  $cv->send if ($bus && $input =~ /\n/);
		  return;
	   },
	);

	my $w = AnyEvent->idle(cb => sub {
		my $size = $midi_in->bufsize;
		my $midi_bytes;
		read($fh, $midi_bytes, $size);
		$decoder->decode($midi_bytes);		
	});

	$cv->recv;

	$self->{midi_bus} = $bus;
}


sub init_output {
	my $self = shift;
	
	my $handle = AnyEvent::Run->new(
		cmd      => ['aplay', '-f', 's16_le', '-r', '44100'],
		priority => 19,
	);
	
	$self->{output} = $handle;
}

sub init_midi_hook {
	my $self = shift;
	my $hook = shift;
	
	my $midi_in = $self->{midi_in};
	
	my $fh = $midi_in->get_fh;
	$self->{midi_fh} = $fh;
	
	$self->{midi_decoder} = MIDI::Stream::Decoder->new;
	$self->{midi_decoder}->attach_callback( all => sub {
		my ($event) = @_;
		my @a = $event->as_arrayref->@*;
		if ($a[0] eq $self->{midi_bus}) {
			$hook->($a[-1]);
		}
	});
}

sub wait_midi {
	my $self = shift;
	
	my $midi_in = $self->{midi_in};
	my $fh = $self->{midi_fh};
	
	my $size = $midi_in->bufsize;
	my $midi_bytes;
	read($fh, $midi_bytes, $size);
	$self->{midi_decoder}->decode($midi_bytes);	
}


sub push_output {
	my $self = shift;
	
	my $r = '';
	for (@{$self->{buffer}}) {
		my $s = int ($_ * 32767 + 0.5);
		$r .= pack('s', $s);
	}
	$self->{buffer} = [];
	
	$self->{output}->push_write($r);
}

1;
