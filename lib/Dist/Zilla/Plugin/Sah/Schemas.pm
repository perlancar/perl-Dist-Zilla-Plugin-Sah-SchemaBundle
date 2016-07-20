package Dist::Zilla::Plugin::Sah::Schemas;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

with (
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules'],
    },
    'Dist::Zilla::Role::PrereqSource',
);

sub munge_files {
    no strict 'refs';

    my $self = shift;

    $self->{_our_schema_modules}  //= {};
    $self->{_used_schema_modules} //= {};

    for my $file (@{ $self->found_files }) {
        unless ($file->isa("Dist::Zilla::File::OnDisk")) {
            $self->log_debug(["skipping %s: not an ondisk file, currently generated file is assumed to be OK", $file->name]);
            return;
        }
        my $file_name = $file->name;
        my $file_content = $file->content;
        if ($file_name =~ m!^lib/((.+)\.pm)$!) {
            my $package_pm = $1;
            my $package = $2; $package =~ s!/!::!g;

            if ($package =~ /^Sah::Schema::/) {
                {
                    local @INC = ("lib", @INC);
                    require $package_pm;
                    $self->{_our_schema_modules}{$package}++;
                }
                my $sch = ${"$package\::schema"};
                my $nsch = Data::Sah::Normalize::normalize_schema($sch);

                # check that schema is already normalized
                {
                    require Data::Dump;
                    require Data::Sah::Normalize;
                    require Text::Diff;
                    my $sch_dmp  = Data::Dump::dump($sch);
                    my $nsch_dmp = Data::Dump::dump($nsch);
                    last if $sch_dmp eq $nsch_dmp;
                    my $diff = Text::Diff::diff(\$sch_dmp, \$nsch_dmp);
                    $self->log_fatal("Schema in $file_name is not normalized, below is the dump diff (- is current, + is normalized): " . $diff);
                }

                # collect other Sah::Schema::* modules that are used, this will
                # be added as prereq
              COLLECT_BASE_SCHEMAS:
                {
                    require Data::Sah::Normalize;
                    require Data::Sah::Resolve;
                    require Data::Sah::Util::Subschema;

                    $self->log_debug(["Finding schema modules required by %s", $package]);

                    my $subschemas;
                    eval {
                        $subschemas = Data::Sah::Util::Subschema::extract_subschemas(
                            {schema_is_normalized => 1},
                            $nsch,
                        );
                    };
                    if ($@) {
                        $self->log(["Can't extract subschemas from schema in %s (%s), skipped", $package, $@]);
                        last COLLECT_BASE_SCHEMAS;
                    }

                    for my $subsch ($nsch, @$subschemas) {
                        my $nsubsch = Data::Sah::Normalize::normalize_schema($subsch);
                        my $res = Data::Sah::Resolve::resolve_schema(
                            {
                                schema_is_normalized => 1,
                                return_intermediates => 1,
                            },
                            $nsubsch);
                        my $intermediates = $res->[2];
                        for my $i (0..$#{$intermediates}-1) {
                            my $mod = "Sah::Schema::$intermediates->[$i]";
                            $self->{_used_schema_modules}{$mod}++;
                        }
                    }
                }

                # set ABSTRACT from schema's summary
                {
                    unless ($file_content =~ m{^#[ \t]*ABSTRACT:[ \t]*([^\n]*)[ \t]*$}m) {
                        $self->log_debug(["Skipping setting ABSTRACT %s: no # ABSTRACT", $file_name]);
                        last;
                    }
                    my $abstract = $1;
                    if ($abstract =~ /\S/) {
                        $self->log_debug(["Skipping setting ABSTRACT %s: already filled (%s)", $file_name, $abstract]);
                        last;
                    }

                    $file_content =~ s{^#\s*ABSTRACT:.*}{# ABSTRACT: $sch->[1]{summary}}m
                        or die "Can't set abstract for " . $file->name;
                    $self->log(["setting abstract for %s (%s)", $file->name, $sch->[1]{summary}]);
                    $file->content($file_content);
                }
            } # Sah::Schema::*
        }
    } # for $file
}

sub register_prereqs {
    my $self = shift;

    #use DD; dd $self->{_used_schema_modules}; dd $self->{_our_schema_modules};
    for my $mod (sort keys %{$self->{_used_schema_modules}}) {
        next if $self->{_our_schema_modules}{$mod};
        $self->log(["Adding prereq to %s", $mod]);
        $self->zilla->register_prereqs({phase=>'runtime'}, $mod);
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Plugin to use when building Sah-Schemas-* distribution

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<dist.ini>:

 [Sah::Schemas]


=head1 DESCRIPTION

This plugin is to be used when building C<Sah-Schemas-*> distribution. It
currently does the following to C<lib/Sah/Schemas/*> .pm files:

=over

=item *

=back

It does the following to C<lib/Sah/Schema/*> .pm files:

=over

=item * Check that schema is already normalized

Otherwise, the build is aborted.

=item * Set module abstract from the schema's summary

=item * Add a prereq to other Sah::Schema::* module if schema depends on those other schemas

=back



=head1 SEE ALSO

L<Pod::Weaver::Plugin::Sah::Schemas>

L<Sah::Schemas>

L<Sah> and L<Data::Sah>
