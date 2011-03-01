package App::UnZipK;

use strict;

use warnings;

use 5.010;

use autodie;

use Archive::Zip qw< :ERROR_CODES :CONSTANTS :MISC_CONSTANTS >;

use Encode qw< encode_utf8 decode >;

use File::Spec::Functions qw< catfile splitpath >;

use POSIX qw< strftime >;

use IO::Prompt;

use Text::Glob qw< match_glob >;

use Fcntl qw< :mode >;

=head1 NAME

App::UnZipK - UnZip for Korean

=head1 VERSION

Version 1.1.0

=cut

our $VERSION = '1.1.0';

=head1 SYNOPSIS

    use App::UnZipK;

    my $archive_name = 'file.zip';

    # Run UnZip-K as zipinfo mode.
    App::UnZipK::zipinfo($archive_name);

    # Run UnZip-K as unzip mode.
    App::UnZipK::unzip($archive_name, { overwrite => 1 });

=head1 SUBROUTINES

=head2 zipinfo

ZipInfo mode(unzip -Z).

=cut

sub zipinfo {
    my ( $archive_name, $zipinfo_time ) = @_;

    _print_archive_name($archive_name);

    my $archive_size = -s $archive_name;

    my $zip = Archive::Zip->new();
    $zip->read($archive_name) == AZ_OK or return;

    my $nr_entries = $zip->numberOfMembers();

    say "Zip file size: $archive_size bytes, number of entries: $nr_entries";

    my $total_uncompressed_size;
    my $total_compressed_size;

    for my $member ( $zip->members() ) {
        $total_uncompressed_size += $member->uncompressedSize();
        $total_compressed_size   += $member->compressedSize();

        say _get_member_info( $member, $zipinfo_time );
    }

    my $compression_ratio = 0.0;
    if ($total_uncompressed_size) {
        $compression_ratio
            = $total_uncompressed_size - $total_compressed_size;
        $compression_ratio /= $total_uncompressed_size;
        $compression_ratio *= 100;
        $compression_ratio += 0.04;    # For compatibility with unzip
    }

    my $format = '%d file%s, %d bytes uncompressed, '
        . "%d bytes compressed:  %.1f%%\n";
    printf $format, $nr_entries, $nr_entries == 1 ? q{} : 's',
        $total_uncompressed_size, $total_compressed_size, $compression_ratio;

    return 1;
}

=head2 unzip

UnZip mode(unzip).

=cut

sub unzip {
    my ( $archive_name, $unzip_option_ref ) = @_;
    my $files_ref  = $unzip_option_ref->{files}  // [];
    my $xfiles_ref = $unzip_option_ref->{xfiles} // [];
    my $exdir      = $unzip_option_ref->{exdir};
    my $crt        = $unzip_option_ref->{crt};
    my $list       = $unzip_option_ref->{list};
    my $pipe       = $unzip_option_ref->{pipe};
    my $test       = $unzip_option_ref->{test};
    my $comment_only     = $unzip_option_ref->{comment_only};
    my $fresh            = $unzip_option_ref->{fresh};
    my $update           = $unzip_option_ref->{update};
    my $case_insensitive = $unzip_option_ref->{case_insensitive};
    my $junk_paths       = $unzip_option_ref->{junk_paths};
    my $never_overwrite  = $unzip_option_ref->{never_overwrite};
    my $overwrite        = $unzip_option_ref->{overwrite};
    my $quiet            = $unzip_option_ref->{quiet};

    if ( !$pipe && !$quiet ) {
        _print_archive_name($archive_name);
    }

    my $zip = Archive::Zip->new();
    $zip->read($archive_name) == AZ_OK or return;

    if ( !$pipe && !$quiet ) {
        _print_archive_comment_of($zip);
    }

    return 1 if $comment_only;

    if ($list) {
        _print_list_header();
    }

    my %file_is_matched;
    my %xfile_is_matched;

    my $total_length = 0;
    my $total_count  = 0;

    my $replace
        = $never_overwrite ? 'None'
        : $overwrite       ? 'All'
        :                    undef;
    $unzip_option_ref->{replace} = \$replace;

    my $error_in_archive;
    $unzip_option_ref->{error} = \$error_in_archive;

MEMBER:
    for my $member ( $zip->members() ) {
        next MEMBER if $junk_paths && $member->isDirectory();

        my $member_name = _decode_name_of($member);

        # Check archive members to be excluded from processing
        my $to_be_excluded = _match_with_globs(
            {   name                => $member_name,
                globs_ref           => $xfiles_ref,
                case_insensitive    => $case_insensitive,
                glob_is_matched_ref => \%xfile_is_matched,
            }
        );
        next MEMBER if $to_be_excluded;

        # Check archive members to be processed
        my $to_be_processed = @{$files_ref} == 0 || _match_with_globs(
            {   name                => $member_name,
                globs_ref           => $files_ref,
                case_insensitive    => $case_insensitive,
                glob_is_matched_ref => \%file_is_matched,
            }
        );
        next MEMBER if !$to_be_processed;

        $total_length += $member->uncompressedSize();
        $total_count++;
        _extract_member( $member, $unzip_option_ref );
    }

    if ($list) {
        _print_list_footer_using( $total_length, $total_count );
    }

    # print caution about unmatched filenames
    for my $file ( grep { !$file_is_matched{$_} } @{$files_ref} ) {
        say "caution: filename not matched:  $file";
    }
    for my $xfile ( grep { !$xfile_is_matched{$_} } @{$xfiles_ref} ) {
        say "caution: excluded filename not matched:  $xfile";
    }

    if ($test) {
        if ($error_in_archive) {
            say "At least one error was detected in $archive_name.";
        }
        elsif ( $total_count == 0 ) {
            say "Caution:  zero files tested in $archive_name.";
        }
        elsif ( @{$files_ref} || @{$xfiles_ref} ) {
            say "No errors detected in $archive_name"
                . " for the $total_count files tested.";
        }
        else {
            say "No errors detected in compressed data of $archive_name.";
        }
    }

    return 1;
}

sub _print_archive_name {
    my ($archive_name) = @_;

    say "Archive:  $archive_name";
    return;
}

sub _get_dos_file_attr_string {
    my ($external_file_attr) = @_;

    my $dos_file_attr_string;

    # Open file handle to "in memory" file held in Perl scalar
    open my $fh, '>', \$dos_file_attr_string;

    # See zipinfo.c in unzip
    print {$fh} 'r';
    print {$fh} $external_file_attr & 0x01 ? '-' : 'w';
    print {$fh} $external_file_attr & 0x10 ? 'x' : '-';
    print {$fh} $external_file_attr & 0x20 ? 'a' : '-';
    print {$fh} $external_file_attr & 0x02 ? 'h' : '-';
    print {$fh} $external_file_attr & 0x04 ? 's' : '-';
    print {$fh} q{ } x 3;

    close $fh;

    return $dos_file_attr_string;
}

# oct('0755') => rwxr-xr-x
sub _get_unix_file_attr_string {
    my $unix_file_attr = shift() & oct('0777');

    my $unix_file_attr_string;

    # Open file handle to "in memory" file held in Perl scalar
    open my $fh, '>', \$unix_file_attr_string;

    # User
    print {$fh} $unix_file_attr & S_IRUSR ? 'r' : '-';
    print {$fh} $unix_file_attr & S_IWUSR ? 'w' : '-';
    print {$fh} $unix_file_attr & S_IXUSR ? 'x' : '-';

    # Group
    print {$fh} $unix_file_attr & S_IRGRP ? 'r' : '-';
    print {$fh} $unix_file_attr & S_IWGRP ? 'w' : '-';
    print {$fh} $unix_file_attr & S_IXGRP ? 'x' : '-';

    # Other
    print {$fh} $unix_file_attr & S_IROTH ? 'r' : '-';
    print {$fh} $unix_file_attr & S_IWOTH ? 'w' : '-';
    print {$fh} $unix_file_attr & S_IXOTH ? 'x' : '-';

    close $fh;

    return $unix_file_attr_string;
}

sub _get_member_info {
    my ( $member, $zipinfo_time ) = @_;

    my $member_info;

    # Open file handle to "in memory" file held in Perl scalar
    open my $fh, '>', \$member_info;

    print {$fh} $member->isDirectory() ? 'd' : '-';

    my $file_attribute_format = $member->fileAttributeFormat();

    if ( $file_attribute_format == FA_MSDOS ) {
        my $external_file_attr = $member->externalFileAttributes();
        print {$fh} _get_dos_file_attr_string($external_file_attr);
    }
    else {
        my $unix_file_attr = $member->unixFileAttributes();
        print {$fh} _get_unix_file_attr_string($unix_file_attr);
    }

    print {$fh} q{ } x 2;

    # e.g. 20 -> 2.0
    print {$fh} sprintf '%.1f', $member->versionMadeBy() / 10;

    print {$fh} q{ };

    print {$fh} $file_attribute_format == FA_MSDOS ? 'fat' : 'unx';

    print {$fh} q{ };

    print {$fh} sprintf '%8d', $member->uncompressedSize();

    print {$fh} q{ };

    if ( $member->isEncrypted() ) {
        print {$fh} $member->isTextFile() ? 'T' : 'B';
    }
    else {
        print {$fh} $member->isTextFile() ? 't' : 'b';
    }

    print {$fh} $member->extraFields() ne q{} ? 'x' : '-';

    print {$fh} q{ };

    if ( $member->compressionMethod() == COMPRESSION_STORED ) {
        print {$fh} 'stor';
    }
    else {
        my $deflating_level
            = $member->bitFlag() & GPBF_DEFLATING_COMPRESSION_MASK;

        if ( $deflating_level == DEFLATING_COMPRESSION_SUPER_FAST ) {
            print {$fh} 'defS';
        }
        elsif ( $deflating_level == DEFLATING_COMPRESSION_FAST ) {
            print {$fh} 'defF';
        }
        elsif ( $deflating_level == DEFLATING_COMPRESSION_NORMAL ) {
            print {$fh} 'defN';
        }
        else {
            print {$fh} 'defX';
        }
    }

    print {$fh} q{ };

    my $format = $zipinfo_time ? '%Y%m%d.%H%M%S' : '%g-%b-%d %H:%M';
    print {$fh} strftime( $format, localtime $member->lastModTime() );

    print {$fh} q{ };

    print {$fh} _decode_name_of($member);

    close $fh;

    return $member_info;
}

sub _print_comment {
    my ($comment) = @_;

    if ( $comment ne q{} ) {
        say $comment;
    }

    return;
}

sub _print_archive_comment_of {
    my ($zip) = @_;

    _print_comment( $zip->zipfileComment() );

    return;
}

sub _print_file_comment_of {
    my ($member) = @_;

    _print_comment( $member->fileComment() );

    return;
}

sub _print_list_header {
    say '  Length      Date    Time    Name';
    say '---------  ---------- -----   ----';

    return;
}

sub _print_list_contents_of {
    my ($member) = @_;

    my $format = "%9u  %s   %s\n";
    printf $format,
        $member->uncompressedSize(),
        strftime( '%F %R', localtime $member->lastModTime() ),
        _decode_name_of($member);

    return;
}

sub _print_list_footer_using {
    my ( $total_length, $total_count ) = @_;

    say '---------                     -------';
    my $format = "%9u                     %u file%s\n";
    printf $format, $total_length, $total_count,
        $total_count == 1 ? q{} : 's';

    return;
}

sub _match_with_globs {
    my ($arg_ref)           = @_;
    my $name                = $arg_ref->{name};
    my $globs_ref           = $arg_ref->{globs_ref};
    my $case_insensitive    = $arg_ref->{case_insensitive};
    my $glob_is_matched_ref = $arg_ref->{glob_is_matched_ref};

    for my $glob ( @{$globs_ref} ) {
        if ( match_glob( $glob, $name )
            || ( $case_insensitive && match_glob( lc $glob, lc $name ) ) )
        {
            $glob_is_matched_ref->{$glob} = 1;
            return 1;
        }
    }

    return;
}

sub _junk_paths {
    my ($path) = @_;

    # Remove directory portion
    return ( splitpath($path) )[2];
}

sub _file_is_newer {
    my ( $member, $file ) = @_;

    return if !-e $file;

    return 1 if $member->lastModTime() <= ( stat $file )[9];

    return;
}

sub _extract_member {
    my ( $member, $unzip_option_ref ) = @_;
    my $replace_ref = $unzip_option_ref->{replace};
    my $exdir       = $unzip_option_ref->{exdir};
    my $crt         = $unzip_option_ref->{crt};
    my $list        = $unzip_option_ref->{list};
    my $pipe        = $unzip_option_ref->{pipe};
    my $test        = $unzip_option_ref->{test};
    my $fresh       = $unzip_option_ref->{fresh};
    my $update      = $unzip_option_ref->{update};
    my $error_ref   = $unzip_option_ref->{error};
    my $junk_paths  = $unzip_option_ref->{junk_paths};
    my $quiet       = $unzip_option_ref->{quiet};

    # Get file name to be extracted
    my $extracted_name = _decode_name_of($member);
    if ( !$crt && !$list && !$pipe && !$test ) {
        if ($junk_paths) {
            $extracted_name = _junk_paths($extracted_name);
        }

        if ( defined $exdir && $exdir ne q{} ) {
            $extracted_name = catfile( $exdir, $extracted_name );
        }
    }

    # Skip non-existing file
    return if $fresh && !$update && !-e $extracted_name;

    # Skip newer file
    return
        if ( $fresh || $update )
        && _file_is_newer( $member, $extracted_name );

    # Check existing file or directory
CHECKING:
    while ( !$crt && !$list && !$pipe && !$test && -e $extracted_name ) {
        return if defined ${$replace_ref} && ${$replace_ref} eq 'None';

        return if -d $extracted_name && $member->isDirectory();

        last CHECKING if defined ${$replace_ref} && ${$replace_ref} eq 'All';

        given ( _get_response_for($extracted_name) ) {
            when ('yes')  { last CHECKING; }
            when ('no')   { return; }
            when ('All')  { ${$replace_ref} = 'All'; last CHECKING; }
            when ('None') { ${$replace_ref} = 'None'; return; }
            when ('rename') { $extracted_name = _get_new_name(); }
            default { warn "invalid response!\n"; }
        }
    }

    if ( !$list && !$pipe && !$test && !$quiet ) {
        _print_progress_using( $member, $extracted_name );
    }

    if ( $crt || $pipe ) {
        $member->extractToFileHandle(*STDOUT) == AZ_OK
            or warn "extract error!\n";
        if ( $crt && !$quiet ) {
            say q{};
        }
    }
    elsif ($list) {
        _print_list_contents_of($member);

        if ( !$quiet ) {
            _print_file_comment_of($member);
        }
    }
    elsif ($test) {
        if ( !$quiet ) {
            printf "    testing: %-22s", $extracted_name;
            my $diff
                = length($extracted_name) - length( $member->fileName() );
            if ( $diff > 0 ) {
                print q{ } x $diff;
            }
        }

        my $crc32 = $member->crc32();
        my $computed_crc32
            = Archive::Zip::computeCRC32( $member->contents() );
        if ( $crc32 == $computed_crc32 ) {
            if ( !$quiet ) {
                say '   OK';
            }
        }
        else {
            ${$error_ref} = 1;

            if ( !$quiet ) {
                printf " bad CRC %08lx  (should be %08lx)\n",
                    $crc32, $computed_crc32;
            }
        }
    }
    else {
        $member->extractToFileNamed($extracted_name) == AZ_OK
            or warn "extract error!\n";
    }

    return;
}

sub _decode_name_of {
    my ($member) = @_;

    # CP949 -> UTF-8
    my $ENCODING = 'cp949';
    return encode_utf8( decode( $ENCODING, $member->fileName() ) );
}

sub _get_response_for {
    my ($extracted_name) = @_;

    my $prompt
        = "replace $extracted_name? [y]es, [n]o, [A]ll, [N]one, [r]ename: ";

    while ( my $response = prompt $prompt ) {
        given ($response) {
            when (/^y/xms) { return 'yes'; }
            when (/^n/xms) { return 'no'; }
            when (/^A/xms) { return 'All'; }
            when (/^N/xms) { return 'None'; }
            when (/^r/xms) { return 'rename'; }
            when (q{})     { warn "error:  invalid response [{ENTER}]\n"; }
            default        { warn "error:  invalid response [$response]\n"; }
        }
    }

    say q{};
    say '(EOF or read error, treating as "[N]one" ...)';
    return 'None';
}

sub _get_new_name {
    my $prompt = 'new name: ';

    while (1) {
        my $new_name = prompt $prompt;
        if ( defined $new_name && $new_name ne q{} ) {

            # Warning: $new_name is an object, not a string.
            return "$new_name";
        }
    }

    return 'noname';    # Cannot happen.
}

sub _print_progress_using {
    my ( $member, $extracted_name ) = @_;

    if ( $member->isDirectory() ) {
        say "  creating: $extracted_name";
    }
    elsif ( $member->desiredCompressionMethod() == COMPRESSION_STORED ) {
        say " extracting: $extracted_name";
    }
    else {
        say "  inflating: $extracted_name";
    }

    return;
}

=head1 URL

L<https://github.com/seungwon0/unzip-k>

=head1 AUTHOR

Seungwon Jeong, C<< <seungwon0 at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<seungwon0 at
gmail.com>, or through the web interface at
L<https://github.com/seungwon0/unzip-k/issues>.  I will be
notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::UnZipK

You can also look for information at:

L<https://github.com/seungwon0/unzip-k>

=head1 LICENSE AND COPYRIGHT

Copyright 2011 Seungwon Jeong.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;    # End of App::UnZipK
