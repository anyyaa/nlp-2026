use strict;
use warnings;
use utf8;
use File::Temp qw(tempdir);
use File::Spec;

sub valid_timestamp {
    my ($value) = @_;
    return 0 unless defined $value;
    return 0 unless $value =~ /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\z/;

    my ($year, $month, $day, $hour, $minute, $second) = ($1, $2, $3, $4, $5, $6);
    return 0 if $year < 1 || $month < 1 || $month > 12;
    return 0 if $hour > 23 || $minute > 59 || $second > 59;

    my @days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
    if ($month == 2 && ($year % 400 == 0 || ($year % 4 == 0 && $year % 100 != 0))) {
        $days[1] = 29;
    }
    return $day >= 1 && $day <= $days[$month - 1];
}

sub read_lines {
    my ($filename) = @_;
    open my $file, '<:encoding(UTF-8)', $filename
        or die "Cannot open '$filename': $!\n";
    my @lines = <$file>;
    close $file or die "Cannot close '$filename': $!\n";
    return \@lines;
}

sub write_text {
    my ($filename, $content) = @_;
    open my $file, '>:encoding(UTF-8)', $filename
        or die "Cannot write '$filename': $!\n";
    print {$file} $content or die "Cannot write '$filename': $!\n";
    close $file or die "Cannot close '$filename': $!\n";
}

sub analyze_lines {
    my ($lines, $from, $to) = @_;
    my %counts = map { $_ => 0 } qw(DEBUG INFO WARN ERROR);
    my @errors;
    my $valid = 0;
    my $invalid = 0;

    for my $raw (@$lines) {
        my $line = $raw;
        $line =~ s/\r?\n\z//;
        $line =~ s/\r\z//;
        next if $line =~ /\A\s*\z/;

        if ($line =~ /\A(\S+)\s+(DEBUG|INFO|WARN|ERROR)\s+(.+?)\s*\z/
            && valid_timestamp($1)) {
            my ($timestamp, $level) = ($1, $2);
            $counts{$level}++;
            $valid++;
            if ($level eq 'ERROR' && $timestamp ge $from && $timestamp le $to) {
                push @errors, "$line\n";
            }
        } else {
            $invalid++;
        }
    }

    return (\%counts, $valid, $invalid, \@errors);
}

sub process_file {
    my ($input, $from, $to, $report_file, $errors_file) = @_;
    die "Invalid start timestamp: $from\n" unless valid_timestamp($from);
    die "Invalid end timestamp: $to\n" unless valid_timestamp($to);
    die "Start timestamp is later than end timestamp\n" if $from gt $to;

    my $lines = read_lines($input);
    my ($counts, $valid, $invalid, $errors) = analyze_lines($lines, $from, $to);

    my $report = "=== Log Analysis ===\n";
    $report .= "Input file: $input\n";
    $report .= "Period: $from to $to\n";
    $report .= "Total valid messages: $valid\n";
    $report .= "Invalid lines: $invalid\n\n";
    $report .= "Messages by level:\n";
    for my $level (qw(DEBUG INFO WARN ERROR)) {
        $report .= "$level: $counts->{$level}\n";
    }
    $report .= "\nErrors in selected period: " . scalar(@$errors) . "\n";

    write_text($report_file, $report);
    write_text($errors_file, join('', @$errors));
    return ($report, $errors);
}

sub run_tests {
    my $temp_dir = tempdir(CLEANUP => 1);
    my $input = File::Spec->catfile($temp_dir, 'test_log.txt');
    my $report = File::Spec->catfile($temp_dir, 'report.txt');
    my $errors_file = File::Spec->catfile($temp_dir, 'errors.txt');

    my $sample = join "\n",
        '2026-10-01T00:00:00 ERROR First boundary',
        '2026-10-01T10:00:00 INFO Started',
        '2026-10-02T13:00:00 WARN Slow response',
        '2026-10-03T23:59:59 ERROR Last boundary',
        '2026-10-04T00:00:00 ERROR Outside period',
        '2026-10-02T10:00:00 DEBUG Cache check',
        '2026-02-30T10:00:00 ERROR Invalid date',
        'bad log line',
        '';
    write_text($input, $sample);

    my ($text, $selected) = process_file(
        $input, '2026-10-01T00:00:00', '2026-10-03T23:59:59', $report, $errors_file
    );

    my $all_tests = 0;
    my $passed = 0;
    my $check = sub {
        my ($name, $ok) = @_;
        $all_tests++;
        $passed++ if $ok;
        print "$name: ", ($ok ? 'PASS' : 'FAIL'), "\n";
    };

    $check->('Count valid lines', $text =~ /Total valid messages: 6\n/);
    $check->('Count invalid lines', $text =~ /Invalid lines: 2\n/);
    $check->('Count levels', $text =~ /DEBUG: 1\nINFO: 1\nWARN: 1\nERROR: 3\n/);
    $check->('Inclusive boundaries', scalar(@$selected) == 2);
    $check->('Exclude later error', join('', @$selected) !~ /Outside period/);
    $check->('Report written to file', join('', @{read_lines($report)}) eq $text);
    $check->('Error file written', join('', @{read_lines($errors_file)}) eq join('', @$selected));
    $check->('Leap day accepted', valid_timestamp('2024-02-29T12:30:00'));
    $check->('Invalid leap day rejected', !valid_timestamp('2026-02-29T12:30:00'));

    my $reversed_rejected = !eval {
        process_file($input, '2026-10-04T00:00:00', '2026-10-03T00:00:00', $report, $errors_file);
        1;
    };
    $check->('Reversed period rejected', $reversed_rejected);

    my $empty = File::Spec->catfile($temp_dir, 'empty.txt');
    write_text($empty, '');
    my ($empty_text) = process_file(
        $empty, '2026-10-01T00:00:00', '2026-10-03T23:59:59', $report, $errors_file
    );
    $check->('Empty log handled', $empty_text =~ /Total valid messages: 0\n/);

    print "\nPassed: $passed/$all_tests\n";
    exit($passed == $all_tests ? 0 : 1);
}

if (@ARGV && $ARGV[0] eq '--test') {
    run_tests();
}

my $input = $ARGV[0] // 'log.txt';
my $from = $ARGV[1] // '2026-10-01T00:00:00';
my $to = $ARGV[2] // '2026-10-03T23:59:59';
my ($report, $errors) = process_file($input, $from, $to, 'report.txt', 'errors_period.txt');

print $report;
print "Saved: report.txt and errors_period.txt\n";
