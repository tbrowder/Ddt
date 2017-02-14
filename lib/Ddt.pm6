use v6;
use Ddt::Template;
use META6;
use File::Find;
use Shell::Command;
use License::Software;
use JSON::Pretty;

unit class Ddt;

sub author { qx{git config --global user.name}.chomp }
sub email { qx{git config --global user.email}.chomp }

my $normalize-path = -> $path {
    $*DISTRO.is-win ?? $path.subst('\\', '/', :g) !! $path;
};
my $to-module = -> $file {
    $normalize-path($file).subst('lib/', '').subst('/', '::', :g).subst(/\.pm6?$/, '');
};
my $to-file = -> $module {
    'lib/' ~ $module.subst('::', '/', :g) ~ '.pm6';
};

has $.module;
has $.module-file;

multi method new {
    my ($module, $module-file) = guess-main-module();
    self.bless(:$module, :$module-file);
}

multi method new($module is copy) {
    $module ~~ s:g/ '-' /::/;
    my $module-file = $to-file($module);
    self.bless(:$module, :$module-file);
}

sub withp6lib(&code) {
    temp %*ENV;
    %*ENV<PERL6LIB> = %*ENV<PERL6LIB>:exists ?? "$*CWD/lib," ~ %*ENV<PERL6LIB> !! "$*CWD/lib";
    &code();
}

sub find-description($module-file) {
    my $content = $module-file.IO.slurp;
    if $content ~~ /^^
        '=' head. \s+ NAME
        \s+
        \S+ \s+ '-' \s+ (\S<-[\n]>*)
    / {
        return $/[0].Str;
    } else {
        return "";
    }
}

# FIXME
sub migrate-travis-yml() {
    my $travis-yml = ".travis.yml".IO;
    return False unless $travis-yml.f;
    my %fix =
        q!  - perl6 -MPanda::Builder -e 'Panda::Builder.build($*CWD)'!
            => q!  - perl6 -MPanda::Builder -e 'Panda::Builder.build(~$*CWD)'!,
        q!  - PERL6LIB=$PWD/blib/lib prove -e perl6 -vr t/!
            => q!  - PERL6LIB=$PWD/lib prove -e perl6 -vr t/!,
        q!  - PERL6LIB=$PWD/blib/lib prove -e perl6 -r t/!
            => q!  - PERL6LIB=$PWD/lib prove -e perl6 -vr t/!,
    ;

    my @lines = $travis-yml.lines;
    my @out;
    my $replaced = False;
    for @lines -> $line {
        if %fix{$line} -> $fix {
            @out.push($fix);
            $replaced = True;
        } else {
            @out.push($line);
        }
    }
    return False unless $replaced;
    given $travis-yml.open(:w) -> $fh {
        LEAVE { $fh.close }
        $fh.say($_) for @out;
    }
    return True;
}

sub find-source-url() {
    try my @line = qx{git remote -v 2>/dev/null};
    return "" unless @line;
    my $url = gather for @line -> $line {
        my ($, $url) = $line.split(/\s+/);
        if $url {
            take $url;
            last;
        }
    }
    return "" unless $url;
    $url .= Str;
    $url ~~ s/^https?/git/; # panda does not support http protocol
    if $url ~~ m/'git@' $<host>=[.+] ':' $<repo>=[<-[:]>+] $/ {
        $url = "git://$<host>/$<repo>";
    } elsif $url ~~ m/'ssh://git@' $<rest>=[.+] / {
        $url = "git://$<rest>";
    }
    $url;
}

sub guess-user-and-repo() {
    my $url = find-source-url();
    return if $url eq "";
    if $url ~~ m{ (git|https?) '://'
        [<-[/]>+] '/'
        $<user>=[<-[/]>+] '/'
        $<repo>=[.+?] [\.git]?
    $} {
        return $/<user>, $/<repo>;
    } else {
        return;
    }
}

sub find-provides() {
    my %provides = find(dir => "lib", name => /\.pm6?$/).list.map(-> $file {
        my $module = $to-module($file.Str);
        $module => $normalize-path($file.Str);
    }).sort;
    %provides;
}

sub guess-main-module() {
    die "Must run in the top directory" unless "lib".IO ~~ :d;
    my @module-files = find(dir => "lib", name => /.pm6?$/).list;
    my $num = @module-files.elems;
    given $num {
        when 0 {
            die "Could not determine main module file";
        }
        when 1 {
            my $f = @module-files[0];
            return ($to-module($f), $f);
        }
        default {
            my $dir = $*CWD.basename;
            $dir ~~ s/^ (perl6|p6) '-' //;
            my $module = $dir.split('-').join('/');
            my @found = @module-files.grep(-> $f { $f ~~ m:i/$module . pm6?$/});
            my $f = do if @found == 0 {
                my @f = @module-files.sort: { $^a.chars <=> $^b.chars };
                @f.shift.Str;
            } elsif @found == 1 {
                @found[0].Str;
            } else {
                my @f = @found.sort: { $^a.chars <=> $^b.chars };
                @f.shift.Str;
            }
            return ($to-module($f), $f);
        }
    }
}

our sub meta-to-json(META6 $meta --> Str:D) {
    my %h = from-json($meta.to-json: :skip-null).pairs.grep: *.value !~~ Empty;
    to-json(%h);
}

=begin pod

=head1 NAME

Ddt - Distribution Development Tool a replacement for mi6

=head1 SYNOPSIS

  > ddt new Foo::Bar # create Foo-Bar distribution
  > cd Foo-Bar
  > ddt build        # build the distribution and re-generate README.md & META6.json
  > ddt test         # Run tests 

=head1 INSTALLATION

  # with zef
  > zef install Ddt

=head1 DESCRIPTION

Ddt is a an authoring tool for Perl6. 

=head2 Features

=item Create a distribution skeleton for Perl6

=item Generate README.md from lib/Main/Module.pm6's pod

=item Generate a META6.json

=item Generate a META test with 

=item Support for different licenses


=head2 Differences to Mi6

=item Support for different licenses via C<License::Software>

=item META6 is generated using C<META6>

=item Meta test

=item Use zef for tests

=item Extended .gitignore

=item Support for different licenses

=item Support for Distributions with a hyphen in the namel

=head1 FAQ

=item How can I manage depends, build-depends, test-depends?

  Write them to META6.json directly :)

=item Where is Changes file?

  TODO

=item Where is the spec of META6.json?

  Maybe https://github.com/perl6/ecosystem/blob/master/spec.pod or http://design.perl6.org/S22.html

=item How do I remove travis badge?

  Remove .travis.yml

=head1 SEE ALSO

L<<https://github.com/tokuhirom/Minilla>>

L<<https://github.com/rjbs/Dist-Zilla>>

=head1 AUTHOR

=item Bahtiar `kalkin-` Gadimov <bahtiar@gadimov.de>

=item Shoichi Kaji <skaji@cpan.org>

=head1 COPYRIGHT AND LICENSE

=item Copyright © 2015 Shoichi Kaji
=item Copyright © 2016-2017 Bahtiar `kalkin-` Gadimov

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
